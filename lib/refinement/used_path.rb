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
      add_reason changeset.include_path?(absolute_path: path)
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
    def add_reason(modification)
      return unless modification

      "#{modification.path} (#{inclusion_reason}) #{modification.type}"
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
        modification, _yaml_diff = changeset.include_yaml_keypath?(absolute_path: path, keypath: yaml_keypath)
        add_reason modification
      end

      # (see UsedPath#to_s)
      def to_s
        "#{path.to_s.inspect} @ #{yaml_keypath.join('.')} (#{inclusion_reason})"
      end

      private

      # (see UsedPath#add_reason)
      def add_reason(modification)
        return unless modification

        "#{modification.path} @ #{yaml_keypath.join('.')} (#{inclusion_reason}) #{modification.type}"
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
      add_reason changeset.include_glob?(absolute_glob: glob)
    end

    # (see UsedPath#to_s)
    def to_s
      "#{glob.to_s.inspect} (#{inclusion_reason})"
    end

    private

    # (see UsedPath#add_reason)
    def add_reason(modification)
      return unless modification

      "#{modification.path} (#{inclusion_reason}) #{modification.type}"
    end
  end
end
