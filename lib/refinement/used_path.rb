# frozen_string_literal: true

module Refinement
  # Represents a path that some target depends upon.
  class UsedPath
    # @return [Pathname] the absolute path to the file
    attr_reader :path
    private :path

    # @return [String] the reason why this path is being used by a target
    attr_reader :inclusion_reason
    private :inclusion_reason

    def initialize(path:, inclusion_reason:)
      @path = path
      @inclusion_reason = inclusion_reason
    end

    # @return [Nil, String] If the path has been modified, a string explaining the modification
    # @param changeset [Changeset] the changeset to search for a modification to this path
    def find_in_changeset(changeset)
      add_reason changeset.find_modification_for_path(absolute_path: path), changeset: changeset
    end

    # @return [Nil, String] If the path has been modified, a string explaining the modification
    # @param changesets [Array<Changeset>] the changesets to search for a modification to this path
    def find_in_changesets(changesets)
      raise ArgumentError, 'Must provide at least one changeset' if changesets.empty?

      changesets.reduce(true) do |explanation, changeset|
        explanation && find_in_changeset(changeset)
      end
    end

    # @return [String]
    # @visibility private
    def to_s
      "#{path.to_s.inspect} (#{inclusion_reason})"
    end

    private

    # @return [Nil, String] A string suitable for user display that explains
    #   why the given modification means a target is modified
    # @param modification [Nil, FileModification]
    # @param changeset [Changeset]
    def add_reason(modification, changeset:)
      return unless modification

      add_changeset_description "#{modification.path} (#{inclusion_reason}) #{modification.type}", changeset: changeset
    end

    # @return [String] A string suitable for user display that explains
    #   why the given modification means a target is modified, including the description
    #   of the changeset that contains the modification
    # @param description [String]
    # @param changeset [Nil, Changeset]
    def add_changeset_description(description, changeset:)
      return description unless changeset&.description

      description + " (#{changeset.description})"
    end

    # Represents a path to a YAML file that some target depends upon,
    # but where only a subset of the YAML is needed to determine a change.
    class YAML < UsedPath
      # @return [Array] the keypath to search for modifications in a YAML document
      attr_reader :yaml_keypath
      private :yaml_keypath

      def initialize(yaml_keypath:, **kwargs)
        super(**kwargs)
        @yaml_keypath = yaml_keypath
      end

      # (see UsedPath#find_in_changeset)
      def find_in_changeset(changeset)
        modification, _yaml_diff = changeset.find_modification_for_yaml_keypath(absolute_path: path, keypath: yaml_keypath)
        add_reason modification, changeset: changeset
      end

      # (see UsedPath#to_s)
      def to_s
        "#{path.to_s.inspect} @ #{yaml_keypath.join('.')} (#{inclusion_reason})"
      end

      private

      # (see UsedPath#add_reason)
      def add_reason(modification, changeset:)
        return unless modification

        keypath_string =
          if yaml_keypath.empty?
            ''
          else
            ' @ ' + yaml_keypath.map { |path| path.to_s =~ /\A[a-zA-Z0-9_]+\z/ ? path : path.inspect }.join('.')
          end
        add_changeset_description "#{modification.path}#{keypath_string} (#{inclusion_reason}) #{modification.type}", changeset: changeset
      end
    end
  end

  # Represents a glob that some target depends upon.
  class UsedGlob
    # @return [String] a relative path glob
    attr_reader :glob
    private :glob

    # (see UsedPath#inclusion_reason)
    attr_reader :inclusion_reason
    private :inclusion_reason

    def initialize(glob:, inclusion_reason:)
      @glob = glob
      @inclusion_reason = inclusion_reason
    end

    # (see UsedPath#find_in_changeset)
    def find_in_changeset(changeset)
      add_reason changeset.find_modification_for_glob(absolute_glob: glob), changeset: changeset
    end

    # (see UsedPath#find_in_changesets)
    def find_in_changesets(changesets)
      raise ArgumentError, 'Must provide at least one changeset' if changesets.empty?

      changesets.reduce(true) do |explanation, changeset|
        explanation && find_in_changeset(changeset)
      end
    end

    # (see UsedPath#to_s)
    def to_s
      "#{glob.to_s.inspect} (#{inclusion_reason})"
    end

    private

    # (see UsedPath#add_reason)
    def add_reason(modification, changeset:)
      return unless modification

      add_changeset_description "#{modification.path} (#{inclusion_reason}) #{modification.type}", changeset: changeset
    end

    # (see UsedPath#add_changeset_description)
    def add_changeset_description(description, changeset:)
      return description unless changeset&.description

      description + " (#{changeset.description})"
    end
  end
end
