module Refinement
  # Called after CocoaPods installation to write an augmenting file that
  # takes into account changes to Pod configuration,
  # as well as the globs used by podspecs to search for files
  class CocoaPodsPostInstallWriter
    attr_reader :aggregate_targets, :config, :repo, :options
    private :aggregate_targets, :config, :repo, :options

    # Initializes a post-install writer with CocoaPods target objects.
    # @return [CocoaPodsPostInstallWriter] a new instance of CocoaPodsPostInstallWriter
    # @param aggregate_targets [Array<Pod::AggregateTarget>]
    # @param config [Pod::Config]
    # @param options [Hash]
    def initialize(aggregate_targets, config, options)
      @aggregate_targets = aggregate_targets
      @config = config
      @repo = config.installation_root
      @options = options || {}
    end

    # Writes the refinement augmenting file to the configured path
    # @return [Void]
    def write!
      write_file options.fetch('output_path', config.sandbox.root.join('pods_refinement.json')), paths_by_target_name
    end

    private

    def write_file(path, hash)
      require 'json'
      File.open(path, 'w') do |f|
        f << JSON.generate(hash) << "\n"
      end
    end

    def paths_by_target_name
      targets = {}
      aggregate_targets.each do |aggregate_target|
        targets[aggregate_target.label] = paths_for_aggregate_target(aggregate_target)
      end
      aggregate_targets.flat_map(&:pod_targets).uniq.each do |pod_target|
        targets.merge! paths_for_pod_targets(pod_target)
      end
      targets
    end

    def paths_for_aggregate_target(aggregate_target)
      paths = []
      if (podfile_path = aggregate_target.podfile.defined_in_file)
        paths << { path: podfile_path.relative_path_from(repo), inclusion_reason: 'Podfile' }
      end
      if (user_project_path = aggregate_target.user_project_path)
        paths << { path: user_project_path.relative_path_from(repo), inclusion_reason: 'user project' }
      end
      paths
    end

    def library_specification?(spec)
      # Backwards compatibility
      if spec.respond_to?(:library_specification?, false)
        spec.library_specification?
      else
        !spec.test_specification?
      end
    end

    def specification_paths_from_pod_target(pod_target)
      pod_target
        .target_definitions
        .map(&:podfile)
        .uniq
        .flat_map do |podfile|
        podfile
          .dependencies
          .select { |d| d.root_name == pod_target.pod_name }
          .map { |d| (d.external_source || {})[:path] }
          .compact
      end.uniq
    end

    def paths_for_pod_targets(pod_target)
      file_accessors_by_target_name = pod_target.file_accessors.group_by do |fa|
        if library_specification?(fa.spec)
          pod_target.label
        elsif pod_target.respond_to?(:non_library_spec_label)
          pod_target.non_library_spec_label(fa.spec)
        else
          pod_target.test_target_label(fa.spec)
        end
      end

      pod_dir = pod_target.sandbox.pod_dir(pod_target.pod_name).relative_path_from(repo)

      spec_paths = specification_paths_from_pod_target(pod_target)

      file_accessors_by_target_name.each_with_object({}) do |(label, file_accessors), h|
        paths = [
          { path: 'Podfile.lock',
            inclusion_reason: 'CocoaPods lockfile',
            yaml_keypath: ['SPEC CHECKSUMS', pod_target.pod_name] }
        ]
        spec_paths.each { |path| paths << { path: path, inclusion_reason: 'podspec' } }

        Pod::Validator::FILE_PATTERNS.each do |pattern|
          file_accessors.each do |fa|
            globs = fa.spec_consumer.send(pattern)
            globs = globs.values.flatten if globs.is_a?(Hash)
            globs.each do |glob|
              paths << { glob: pod_dir.join(glob), inclusion_reason: pattern.to_s.tr('_', ' ').chomp('s') }
            end
          end
        end

        h[label] = paths.uniq
      end
    end
  end
end
