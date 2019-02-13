module SpecHelper
  module DSL
    def build_changeset(*args, &blk)
      ChangesetBuilder.new(*args).tap { |cb| cb.instance_eval(&blk) if blk }.changeset
    end

    class ChangesetBuilder
      def initialize
        @modifications = []
      end

      def file(path, type: :changed, prior_path: nil, prior_content: nil, current_content: nil)
        @modifications << Refinement::Changeset::FileModification.new(
          path: Pathname(path),
          type: type,
          prior_path: (Pathname(prior_path) if prior_path),
          contents_reader: -> { current_content },
          prior_contents_reader: -> { prior_content }
        )
      end

      def changeset
        Refinement::Changeset.new(
          modifications: @modifications,
          repository: Pathname('/repository')
        )
      end
    end

    def build_project(*args, &blk)
      ProjectBuilder.new(*args).tap { |pb| pb.instance_eval(&blk) if blk }.project
    end

    class ProjectBuilder
      def initialize
        @project = Xcodeproj::Project.new('/repository/project.xcodeproj')
      end
      attr_reader :project

      def target(name, type: :library, platform: :ios, &blk)
        @project.new_target(type, name, platform).tap do |target|
          TargetBuilder.new(target).instance_eval(&blk) if blk
        end
      end

      class TargetBuilder
        def initialize(target)
          @target = target
        end

        def source_files(*names)
          @target.add_file_references(names.map { |n| @target.project.new_file(n) })
        end

        def build_settings(settings)
          @target.build_configurations.each { |bc| bc.build_settings.merge!(settings) }
        end

        def method_missing(name, *args, &blk)
          if @target.respond_to?(name)
            @target.send(name, *args, &blk)
          else
            super
          end
        end

        def respond_to_missing?(name)
          super || @target.respond_to?(name)
        end
      end
    end

    def changes(level:, augmenting_paths_by_target: {})
      analyzer = Refinement::Analyzer.new(changeset: changeset, workspace_path: nil, projects: [project], augmenting_paths_yaml_files: nil, augmenting_paths_by_target: augmenting_paths_by_target)
      annotated_targets = analyzer.annotate_targets!
      Hash[annotated_targets.map do |annotated_target|
        change_reason = annotated_target.change_reason(level: level)
        change_reason = change_reason.to_s if change_reason
        [annotated_target.xcode_target.name, change_reason]
      end]
    end
  end
end
