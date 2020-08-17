# frozen_string_literal: true

module Refinement
  # Analyzes changes in a repository
  # and determines how those changes impact the targets in Xcode projects in the workspace.
  class Analyzer
    attr_reader :changesets, :workspace_path, :augmenting_paths_yaml_files
    private :changesets, :workspace_path, :augmenting_paths_yaml_files

    # Initializes an analyzer with changesets, projects, and augmenting paths.
    # @param changesets [Array<Changeset>]
    # @param workspace_path [Pathname] path to a root workspace or project,
    #   must be `nil` if `projects` are specified explicitly
    # @param projects [Array<Xcodeproj::Project>] projects to find targets in,
    #   must not be specified if `workspace_path` is not `nil`
    # @param augmenting_paths_yaml_files [Array<Pathname>] paths to YAML files that provide augmenting paths by target,
    #   must be `nil` if `augmenting_paths_by_target` are specified explicitly
    # @param augmenting_paths_by_target [Hash<String, Array>] arrays of hashes keyed by target name
    #  (or '*' for all targets)
    #  describing paths or globs that each target should be considered to be using,
    #  must not be specified if `augmenting_paths_yaml_files` is not `nil`
    #
    # @raise [ArgumentError] when conflicting arguments are given
    #
    def initialize(changesets:, workspace_path:, projects: nil,
                   augmenting_paths_yaml_files:, augmenting_paths_by_target: nil)

      @changesets = changesets

      raise ArgumentError, 'Can only specify one of workspace_path and projects' if workspace_path && projects

      @workspace_path = workspace_path
      @projects = projects

      raise ArgumentError, 'Can only specify one of augmenting_paths_yaml_files and augmenting_paths_by_target' if augmenting_paths_yaml_files && augmenting_paths_by_target

      @augmenting_paths_yaml_files = augmenting_paths_yaml_files
      @augmenting_paths_by_target = augmenting_paths_by_target
    end

    # @return [Array<AnnotatedTarget>] targets from the projects annotated with their changes, based upon
    #   the changeset
    def annotate_targets!
      @annotate_targets ||= annotated_targets
    end

    # @param scheme_path [Pathname] the absolute path to the scheme to be filtered
    # @param change_level [Symbol] the change level at which a target must have changed in order
    #  to remain in the scheme. defaults to `:full_transitive`
    # @param filter_when_scheme_has_changed [Boolean] whether the scheme should be filtered
    #   even when the changeset includes the scheme's path as changed.
    #   Defaults to `false`
    # @param log_changes [Boolean] whether modifications to the scheme are logged.
    #   Defaults to `false`
    # @param filter_scheme_for_build_action [:building, :testing]
    #   The xcodebuild action the scheme is being filtered for. The currently supported values are
    #   `:building` and `:testing`, with the only difference being `BuildActionEntry` are not
    #   filtered out when building for testing, since test action macro expansion could
    #   depend on a build entry being present.
    # @return [Xcodeproj::XCScheme] a scheme whose unchanged targets have been removed
    def filtered_scheme(scheme_path:, change_level: :full_transitive, filter_when_scheme_has_changed: false, log_changes: false,
                        filter_scheme_for_build_action:)
      scheme = Xcodeproj::XCScheme.new(scheme_path)

      sections_to_filter =
        case filter_scheme_for_build_action
        when :building
          %w[BuildActionEntry TestableReference]
        when :testing
          # don't want to filter out build action entries running
          # xcodebuild build-for-testing / test, since the test action could have a macro expansion
          # that depends upon one of the build targets.
          %w[TestableReference]
        else
          raise ArgumentError,
                'The supported values for the `filter_scheme_for_build_action` parameter are: [:building, :testing]. ' \
                "Given: #{filter_scheme_for_build_action.inspect}."
        end

      if !filter_when_scheme_has_changed &&
         UsedPath.new(path: Pathname(scheme_path), inclusion_reason: 'scheme').find_in_changesets(changesets)
        return scheme
      end

      changes_by_suite_name = Hash[annotate_targets!
                              .map { |at| [at.xcode_target.name, at.change_reason(level: change_level)] }]

      doc = scheme.doc

      xpaths = sections_to_filter.map { |section| "//*/#{section}/BuildableReference" }
      xpaths.each do |xpath|
        doc.get_elements(xpath).to_a.each do |buildable_reference|
          suite_name = buildable_reference.attributes['BlueprintName']
          if (change_reason = changes_by_suite_name[suite_name])
            puts "#{suite_name} changed because #{change_reason}" if log_changes
            next
          end
          puts "#{suite_name} did not change, removing from scheme" if log_changes
          buildable_reference.parent.remove
        end
      end

      if filter_scheme_for_build_action == :testing
        doc.get_elements('//*/BuildActionEntry/BuildableReference').to_a.each do |buildable_reference|
          suite_name = buildable_reference.attributes['BlueprintName']
          if (change_reason = changes_by_suite_name[suite_name])
            puts "#{suite_name} changed because #{change_reason}" if log_changes
            next
          end
          puts "#{suite_name} did not change, setting to not build for testing" if log_changes
          buildable_reference.parent.attributes['buildForTesting'] = 'NO'
        end
      end

      scheme
    end

    # @return [String] a string suitable for user display that explains target changes
    # @param include_unchanged_targets [Boolean] whether targets that have not changed should also be displayed
    # @param change_level [Symbol] the change level used for computing whether a target has changed
    def format_changes(include_unchanged_targets: false, change_level: :full_transitive)
      annotate_targets!.group_by { |target| target.xcode_target.project.path.to_s }.sort_by(&:first)
                       .map do |project, annotated_targets|
        changes = annotated_targets.sort_by { |annotated_target| annotated_target.xcode_target.name }
                                   .map do |annotated_target|
          change_reason = annotated_target.change_reason(level: change_level)
          next if !include_unchanged_targets && !change_reason

          change_reason ||= 'did not change'
          "\t#{annotated_target.xcode_target}: #{change_reason}"
        end.compact
        "#{project}:\n#{changes.join("\n")}" unless changes.empty?
      end.compact.join("\n")
    end

    private

    # @return [Array<Xcodeproj::Project>]
    def projects
      @projects ||= find_projects(workspace_path)
    end

    # @return [Hash<String,Array<Hash>>]
    def augmenting_paths_by_target
      @augmenting_paths_by_target ||= begin
        require 'yaml'
        augmenting_paths_yaml_files.reduce({}) do |augmenting_paths_by_target, yaml_file|
          yaml_file = Pathname(yaml_file).expand_path(changesets.first.repository)
          yaml = YAML.safe_load(yaml_file.read)
          augmenting_paths_by_target.merge(yaml) do |_target_name, prior_paths, new_paths|
            prior_paths + new_paths
          end
        end
      end
    end

    # @return [Array<AnnotatedTarget>] targets in the given list of Xcode projects,
    #   annotated according to the given changeset
    def annotated_targets
      workspace_modification = find_workspace_modification_in_changesets
      project_changes = Hash[projects.map do |project|
        [project, find_project_modification_in_changesets(project: project) || workspace_modification]
      end]

      require 'tsort'
      targets = projects.flat_map(&:targets)
      targets_by_uuid = Hash[targets.map { |t| [t.uuid, t] }]
      targets_by_name = Hash[targets.map { |t| [t.name, t] }]
      targets_by_product_name = targets.each_with_object({}) do |t, h|
        next unless t.respond_to?(:product_reference)
        h[File.basename(t.product_reference.path)] = t
        h[File.basename(t.product_reference.name)] = t if t.product_reference.name
      end

      find_dep = ->(td) { targets_by_uuid[td.native_target_uuid] || targets_by_name[td.name] }
      target_deps = lambda do |target|
        target_dependencies = []
        target.dependencies.each do |td|
          target_dependencies << find_dep[td]
        end

        # TODO: also resolve OTHER_LDFLAGS?
        # yay auto-linking
        if (phase = target.frameworks_build_phases)
          phase.files_references.each do |fr|
            if (dt = fr&.path && targets_by_product_name[File.basename(fr.path)])
              target_dependencies << dt
            end
          end
        end

        target_dependencies
      end

      targets = TSort.tsort(
        ->(&b) { targets.each(&b) },
        ->(target, &b) { target_deps[target].each(&b) }
      )

      targets.each_with_object({}) do |target, h|
        change_reason = project_changes[target.project] || find_target_modification_in_changesets(target: target)

        h[target] = AnnotatedTarget.new(
          target: target,
          dependencies: target_deps[target].map { |td| h.fetch(td) },
          change_reason: change_reason
        )
      end.values
    end

    # @return [Array<Xcodeproj::Project>] the projects found by walking the
    #  project/workspace at the given path
    # @param  path [Pathname] path to a `.xcodeproj` or `.xcworkspace` on disk
    def find_projects(path)
      seen = {}
      find_projects_cached = lambda do |project_path|
        return if seen.key?(project_path)

        case File.extname(project_path)
        when '.xcodeproj'
          project = Xcodeproj::Project.open(project_path)
          seen[project_path] = project
          project.files.each do |file_reference|
            next unless File.extname(file_reference.path) == '.xcodeproj'

            find_projects_cached[file_reference.real_path]
          end
        when '.xcworkspace'
          workspace = Xcodeproj::Workspace.new_from_xcworkspace(project_path)
          workspace.file_references.each do |file_reference|
            next unless File.extname(file_reference.path) == '.xcodeproj'

            find_projects_cached[file_reference.absolute_path(File.dirname(project_path))]
          end
        else
          raise ArgumentError, "Unknown path #{project_path.inspect}"
        end
      end
      find_projects_cached[path]

      seen.values
    end

    # @yieldparam used_path [UsedPath] an absolute path that belongs to the given target
    # @return [Void]
    # @param target [Xcodeproj::Project::AbstractTarget]
    def target_each_file_path(target:)
      return enum_for(__method__, target: target) unless block_given?

      expand_build_settings = lambda do |s|
        return [s] unless s =~ /\$(?:\{([_a-zA-Z0-0]+?)\}|\(([_a-zA-Z0-0]+?)\))/

        match, key = Regexp.last_match.values_at(0, 1, 2).compact
        substitutions = target.resolved_build_setting(key, true).values.compact.uniq
        substitutions.flat_map do |sub|
          expand_build_settings[s.gsub(match, sub)]
        end
      end

      target.build_configuration_list.build_configurations.each do |build_configuration|
        ref = build_configuration.base_configuration_reference
        next unless ref

        yield UsedPath.new(path: ref.real_path,
                           inclusion_reason: "base configuration reference for #{build_configuration}")
      end

      target.build_phases.each do |build_phase|
        build_phase.files_references.each do |fr|
          next unless fr

          yield UsedPath.new(path: fr.real_path,
                             inclusion_reason: "#{build_phase.display_name.downcase.chomp('s')} file")
        end
      end

      target.shell_script_build_phases.each do |shell_script_build_phase|
        %w[input_file_list_paths output_file_list_paths input_paths output_paths].each do |method|
          next unless (paths = shell_script_build_phase.public_send(method))

          file_type = method.tr('_', ' ').chomp('s')
          paths.each do |config_path|
            next unless config_path

            expand_build_settings[config_path].each do |path|
              path = Pathname(path).expand_path(target.project.project_dir)
              yield UsedPath.new(path: path,
                                 inclusion_reason: "#{shell_script_build_phase.name} build phase #{file_type}")
            end
          end
        end
      end

      %w[INFOPLIST_FILE HEADER_SEARCH_PATHS FRAMEWORK_SEARCH_PATHS USER_HEADER_SEARCH_PATHS].each do |build_setting|
        target.resolved_build_setting(build_setting, true).each_value do |paths|
          Array(paths).each do |path|
            next unless path

            path = Pathname(path).expand_path(target.project.project_dir)
            yield UsedPath.new(path: path, inclusion_reason: "#{build_setting} value")
          end
        end
      end
    end

    # @return [FileModification,Nil] a modification to a file that is used by the given target, or `nil`
    #   if none if found
    # @param target [Xcodeproj::Project::AbstractTarget]
    def find_target_modification_in_changesets(target:)
      augmenting_paths = used_paths_from_augmenting_paths_by_target[target.name]
      find_in_changesets = ->(path) { path.find_in_changesets(changesets) }
      Refinement.map_find(augmenting_paths, &find_in_changesets) ||
        Refinement.map_find(target_each_file_path(target: target), &find_in_changesets)
    end

    # @yieldparam used_path [UsedPath] an absolute path that belongs to the given project
    # @return [Void]
    # @param project [Xcodeproj::Project]
    def project_each_file_path(project:)
      return enum_for(__method__, project: project) unless block_given?

      yield UsedPath.new(path: project.path, inclusion_reason: 'project directory')

      project.root_object.build_configuration_list.build_configurations.each do |build_configuration|
        ref = build_configuration.base_configuration_reference
        next unless ref

        yield UsedPath.new(path: ref.real_path,
                           inclusion_reason: "base configuration reference for #{build_configuration}")
      end
    end

    # # @return [FileModification,Nil] a modification to a file that is directly used by the given project, or `nil`
    #   if none if found
    # @note This method does not take into account whatever file paths targets in the project may reference
    # @param project [Xcodeproj::Project]
    def find_project_modification_in_changesets(project:)
      Refinement.map_find(project_each_file_path(project: project)) do |path|
        path.find_in_changesets(changesets)
      end
    end

    # @return [FileModification,Nil] a modification to the workspace itself, or `nil`
    #   if none if found
    # @note This method does not take into account whatever file paths projects or
    #   targets in the workspace path may reference
    def find_workspace_modification_in_changesets
      return unless workspace_path

      UsedPath.new(path: workspace_path, inclusion_reason: 'workspace directory')
              .find_in_changesets(changesets)
    end

    # @return [Hash<String,UsedPath>]
    def used_paths_from_augmenting_paths_by_target
      @used_paths_from_augmenting_paths_by_target ||= begin
        repo = changesets.first.repository
        used_paths_from_augmenting_paths_by_target =
          augmenting_paths_by_target.each_with_object({}) do |(name, augmenting_paths), h|
            h[name] = augmenting_paths.map do |augmenting_path|
              case augmenting_path.keys.sort
              when %w[inclusion_reason path], %w[inclusion_reason path yaml_keypath]
                kwargs = {
                  path: Pathname(augmenting_path['path']).expand_path(repo),
                  inclusion_reason: augmenting_path['inclusion_reason']
                }
                if augmenting_path.key?('yaml_keypath')
                  kwargs[:yaml_keypath] = augmenting_path['yaml_keypath']
                  UsedPath::YAML.new(**kwargs)
                else
                  UsedPath.new(**kwargs)
                end
              when %w[glob inclusion_reason]
                UsedGlob.new(glob: File.expand_path(augmenting_path['glob'], repo),
                             inclusion_reason: augmenting_path['inclusion_reason'])
              else
                raise ArgumentError,
                      "unhandled set of keys in augmenting paths dictionary entry: #{augmenting_path.keys.inspect}"
              end
            end
          end
        wildcard_paths = used_paths_from_augmenting_paths_by_target.fetch('*', [])

        Hash.new do |h, k|
          h[k] = wildcard_paths + used_paths_from_augmenting_paths_by_target.fetch(k, [])
        end
      end
    end
  end
end
