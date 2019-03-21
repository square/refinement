require 'claide'

module Refinement
  # @visibility private
  class CLI < CLAide::Command
    self.abstract_command = true
    self.command = 'refine'
    self.version = VERSION

    self.summary = 'Generates a list of Xcode targets to build & test as a result of a diff'

    def self.options
      super + [
        ['--repository=REPOSITORY', 'Path to repository'],
        ['--workspace=WORKSPACE_PATH', 'Path to project or workspace'],
        ['--scheme=SCHEME_PATH', 'Path to scheme to be filtered'],
        ['--augmenting-paths-yaml-files=PATH1,PATH2...', 'Paths to augmenting yaml files, relative to the repository path'],
        ['--[no-]print-changes', 'Print the change reason for changed targets'],
        ['--[no-]print-scheme-changes', 'Print the change reason for targets in the given scheme'],
        ['--change-level=LEVEL', 'Change level at which a target must have changed in order to be considered changed. ' \
                                 'One of `full-transitive`, `itself`, or an integer'],
        ['--filter-scheme-for-build-action=BUILD_ACTION', 'The xcodebuild action the scheme (if given) is filtered for. ' \
                                                          'One of `building` or `testing`.']
      ]
    end

    def initialize(argv)
      @repository = argv.option('repository', '.')
      @workspace = argv.option('workspace')
      @scheme = argv.option('scheme')
      @augmenting_paths_yaml_files = argv.option('augmenting-paths-yaml-files', '')
      @print_changes = argv.flag?('print-changes', false)
      @print_scheme_changes = argv.flag?('print-scheme-changes', false)
      @change_level = argv.option('change-level', 'full-transitive')
      @filter_scheme_for_build_action = argv.option('filter-scheme-for-build-action', 'testing').to_sym

      super
    end

    def run
      changeset = compute_changeset

      analyzer = Refinement::Analyzer.new(changeset: changeset,
                                          workspace_path: @workspace,
                                          augmenting_paths_yaml_files: @augmenting_paths_yaml_files)
      analyzer.annotate_targets!

      puts analyzer.format_changes if @print_changes

      return unless @scheme
      analyzer.filtered_scheme(scheme_path: @scheme, log_changes: @print_scheme_changes, filter_scheme_for_build_action: @filter_scheme_for_build_action)
              .save_as(@scheme.gsub(%r{\.(xcodeproj|xcworkspace)/.+}, '.\1'), File.basename(@scheme, '.xcscheme'), true)
    end

    def validate!
      super

      File.directory?(@repository) || help!("Unable to find a repository at #{@repository.inspect}")

      @workspace || help!('Must specify a project or workspace path')
      File.directory?(@workspace) || help!("Unable to find a project or workspace at #{@workspace.inspect}")

      @augmenting_paths_yaml_files = @augmenting_paths_yaml_files.split(',')
      @augmenting_paths_yaml_files.each do |yaml_path|
        yaml_path = File.join(@repository, yaml_path)
        File.file?(yaml_path) || help!("Unable to find a YAML file at #{yaml_path.inspect}")

        require 'yaml'
        begin
          YAML.safe_load(File.read(yaml_path))
        rescue StandardError => e
          help! "Failed to load YAML file at #{yaml_path.inspect} (#{e})"
        end
      end

      File.file?(@scheme) || help!("Unabled to find a scheme at #{@scheme.inspect}") if @scheme

      @change_level =
        case @change_level
        when 'full-transitive' then :full_transitive
        when 'itself' then :itself
        when /\A\d+\z/ then [:at_most_n_away, @change_level.to_i]
        else help! "Unknown change level #{@change_level.inspect}"
        end
    end

    # @visibility private
    class Git < CLI
      self.summary = 'Generates a list of Xcode targets to build & test as a result of a git diff'

      def self.options
        super + [
          ['--base-revision=SHA', 'Base revision to compute the git diff against']
        ]
      end

      def initialize(argv)
        @base_revision = argv.option('base-revision')

        super
      end

      def validate!
        super

        @base_revision || help!('Must specify a base revision')
      end

      private

      def compute_changeset
        Refinement::Changeset.from_git(repository: Pathname(@repository), base_revision: @base_revision)
      end
    end
  end
end
