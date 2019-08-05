module Refinement
  class Changeset
    # Represents a modification to a single file or directory on disk
    class FileModification
      # @return [Symbol] the change type for directories
      DIRECTORY_CHANGE_TYPE = :'had contents change'

      # @return [Pathname] the path to the modified file
      attr_reader :path

      # @return [Pathname, Nil] the prior path to the modified file, or `nil` if it was not renamed or copied
      attr_reader :prior_path

      # @return [#to_s] the type of change that happened to this file
      attr_reader :type

      def initialize(path:, type:,
                     prior_path: nil,
                     contents_reader: -> { nil },
                     prior_contents_reader: -> { nil })
        @path = path
        @type = type
        @prior_path = prior_path
        @contents_reader = contents_reader
        @prior_contents_reader = prior_contents_reader
      end

      # @visibility private
      def to_s
        case type
        when DIRECTORY_CHANGE_TYPE
          "contents of dir `#{path}` changed"
        else
          message = "file `#{path}` #{type}"
          message += " (from #{prior_path})" if prior_path
          message
        end
      end

      # @visibility private
      def inspect
        "#<#{self.class} path=#{path.inspect} type=#{type.inspect} prior_path=#{prior_path.inspect}" \
          " contents=#{contents.inspect} prior_contents=#{prior_contents.inspect}>"
      end

      # @visibility private
      def hash
        path.hash ^ type.hash
      end

      # @visibility private
      def ==(other)
        return unless other.is_a?(FileModification)
        (path == other.path) && (type == other.type) && prior_path == other.prior_path
      end

      # @visibility private
      def eql?(other)
        return unless other.is_a?(FileModification)
        path.eql?(other.path) && type.eql?(other.type) && prior_path.eql?(other.prior_path)
      end

      # @return [String,Nil] a YAML string representing the diff of the file
      #  from the prior revision to the current revision at the given keypath
      #  in the YAML, or `nil` if there is no diff
      # @param keypath [Array] a list of indices passed to `dig`.
      #  An empty array is equivalent to the entire YAML document
      def yaml_diff(keypath)
        require 'yaml'

        @cached_yaml ||= {}

        dig_yaml = lambda do |yaml, path|
          return yaml if DOES_NOT_EXIST == yaml
          object = @cached_yaml[path] ||= YAML.safe_load(yaml, [Symbol])
          if keypath.empty?
            object
          elsif object.respond_to?(:dig)
            object.dig(*keypath)
          else # backwards compatibility
            keypath.reduce(object) do |acc, elem|
              acc[elem]
            end
          end
        end

        prior = dig_yaml[prior_contents, :prior]
        current = dig_yaml[contents, :current]

        require 'xcodeproj/differ'

        return unless (diff = Xcodeproj::Differ.diff(
          prior,
          current,
          key_1: 'prior_revision',
          key_2: 'current_revision'
        ))

        diff.to_yaml.prepend("#{path} changed at keypath #{keypath.inspect}\n")
      end

      DOES_NOT_EXIST = Object.new.tap do |o|
        class << o
          def to_s
            'DOES NOT EXISTS'
          end
          alias_method :inspect, :to_s
        end
      end.freeze
      private_constant :DOES_NOT_EXIST

      # @return [String] the current contents of the file
      def contents
        @contents ||=
          begin
            @contents_reader[].tap { @contents_reader = nil } || DOES_NOT_EXIST
          rescue StandardError
            DOES_NOT_EXIST
          end
      end

      # @return [String] the prior contents of the file
      def prior_contents
        @prior_contents ||=
          begin
            @prior_contents_reader[].tap { @prior_contents_reader = nil } || DOES_NOT_EXIST
          rescue StandardError
            DOES_NOT_EXIST
          end
      end
    end
  end
end
