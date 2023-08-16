# frozen_string_literal: true

require 'cocoapods/executable'
require 'set'

module Sq
  module Refinement
    # Represents a set of changes in a repository between a prior revision and the current state
    class Changeset
      # An error that happens when computing a git diff
      class GitError < Error; end
      require 'sq/refinement/changeset/file_modification'

      # @return [Pathname] the path to the repository
      attr_reader :repository
      # @return [Array<FileModification>] the modifications in the changeset
      attr_reader :modifications
      # @return [Hash<Pathname,FileModification>] modifications keyed by relative path
      attr_reader :modified_paths
      # @return [Hash<Pathname,FileModification>] modifications keyed by relative path
      attr_reader :modified_absolute_paths
      # @return [String] a desciption of the changeset
      attr_reader :description

      private :modifications, :modified_paths, :modified_absolute_paths

      def initialize(repository:, modifications:, description: nil)
        @repository = repository
        @modifications = self.class.add_directories(modifications).uniq.freeze
        @description = description

        @modified_paths = {}
        @modifications
          .each { |mod| @modified_paths[mod.path] = mod }
          .each { |mod| @modified_paths[mod.prior_path] ||= mod if mod.prior_path }
        @modified_paths.freeze

        @modified_absolute_paths = {}
        @modified_paths
          .each { |path, mod| @modified_absolute_paths[path.expand_path(repository).freeze] = mod }
        @modified_absolute_paths.freeze
      end

      # @visibility private
      # @return [Array<FileModification>] file modifications that include modifications for each
      #                                   directory that has had a child modified
      # @param  modifications [Array<FileModification>] The modifications to add directory modifications to
      def self.add_directories(modifications)
        dirs = Set.new
        add = lambda { |path|
          break unless dirs.add?(path)

          add[path.dirname]
        }
        modifications.each do |mod|
          add[mod.path.dirname]
          add[mod.prior_path.dirname] if mod.prior_path
        end
        modifications +
          dirs.map { |d| FileModification.new(path: Pathname("#{d}/").freeze, type: FileModification::DIRECTORY_CHANGE_TYPE) }
      end

      # @return [FileModification,Nil] the changeset for the given absolute path,
      #   or `nil` if the given path is un-modified
      # @param absolute_path [Pathname]
      def find_modification_for_path(absolute_path:)
        modified_absolute_paths[absolute_path]
      end

      # @return [Array<String>] An array of patterns converted from a
      #         {Dir.glob} pattern to patterns that {File.fnmatch} can handle.
      #         This is used by the {#relative_glob} method to emulate
      #         {Dir.glob}.
      #
      #   The expansion provides support for:
      #
      #   - Literals
      #
      #       dir_glob_equivalent_patterns('{file1,file2}.{h,m}')
      #       => ["file1.h", "file1.m", "file2.h", "file2.m"]
      #
      #   - Matching the direct children of a directory with `**`
      #
      #       dir_glob_equivalent_patterns('Classes/**/file.m')
      #       => ["Classes/**/file.m", "Classes/file.m"]
      #
      # @param [String] pattern   A {Dir#glob} like pattern.
      #
      def dir_glob_equivalent_patterns(pattern)
        pattern = pattern.gsub('/**/', '{/**/,/}')
        values_by_set = {}
        pattern.scan(/\{[^}]*\}/) do |set|
          values = set.gsub(/[{}]/, '').split(',', -1)
          values_by_set[set] = values
        end

        if values_by_set.empty?
          [pattern]
        else
          patterns = [pattern]
          values_by_set.each do |set, values|
            patterns = patterns.flat_map do |old_pattern|
              values.map do |value|
                old_pattern.gsub(set, value)
              end
            end
          end
          patterns
        end
      end
      private :dir_glob_equivalent_patterns

      # @return [FileModification,Nil] the modification for the given absolute glob,
      #   or `nil` if no files matching the glob were modified
      # @note Will only return a single (arbitrary) matching modification, even if there are
      #   multiple modifications that match the glob
      # @param absolute_glob [String] a glob pattern for absolute paths, suitable for an invocation of `Dir.glob`
      def find_modification_for_glob(absolute_glob:)
        absolute_globs = dir_glob_equivalent_patterns(absolute_glob)
        _path, modification = modified_absolute_paths.find do |absolute_path, _modification|
          absolute_globs.any? do |glob|
            File.fnmatch?(glob, absolute_path, File::FNM_CASEFOLD | File::FNM_PATHNAME)
          end
        end
        modification
      end

      # @return [FileModification,Nil] a modification and yaml diff for the keypath at the given absolute path,
      #  or `nil` if the value at the given keypath is un-modified
      # @param absolute_path [Pathname]
      # @param keypath [Array]
      def find_modification_for_yaml_keypath(absolute_path:, keypath:)
        return unless (file_modification = find_modification_for_path(absolute_path:))

        diff = file_modification.yaml_diff(keypath)
        return unless diff

        [file_modification, diff]
      end

      # @return [Changeset] the changes in the given git repository between the given revision and HEAD
      # @param repository [Pathname]
      # @param base_revision [String]
      def self.from_git(repository:, base_revision:)
        raise ArgumentError, "must be given a Pathname for repository, got #{repository.inspect}" unless repository.is_a?(Pathname)
        raise ArgumentError, "must be given a String for base_revision, got #{base_revision.inspect}" unless base_revision.is_a?(String)

        merge_base = git!('merge-base', base_revision, 'HEAD', chdir: repository).strip
        diff = git!('diff', '--raw', '-z', merge_base, chdir: repository)
        modifications = parse_raw_diff(diff, repository:, base_revision: merge_base).freeze

        new(repository:, modifications:, description: "since #{base_revision}")
      end

      CHANGE_TYPES = {
        'was added': 'A',
        'was copied': 'C',
        'was deleted': 'D',
        'was modified': 'M',
        'was renamed': 'R',
        'changed type': 'T',
        'is unmerged': 'U',
        'changed in an unknown way': 'X'
      }.freeze
      private_constant :CHANGE_TYPES

      CHANGE_CHARACTERS = CHANGE_TYPES.invert.freeze
      private_constant :CHANGE_CHARACTERS

      # Parses the raw diff into FileModification objects
      # @return [Array<FileModification>]
      # @param diff [String] a diff generated by `git diff --raw -z`
      # @param repository [Pathname] the path to the repository
      # @param base_revision [String] the base revision the diff was constructed agains
      def self.parse_raw_diff(diff, repository:, base_revision:)
        # since we're null separating the chunks (to avoid dealing with path escaping) we have to reconstruct
        # the chunks into individual diff entries. entries always start with a colon so we can use that to signal if
        # we're on a new entry
        parsed_lines = diff.split("\0").each_with_object([]) do |chunk, lines|
          lines << [] if chunk.start_with?(':')
          lines.last << chunk
        end

        parsed_lines.map do |split_line|
          # change chunk (letter + optional similarity percentage) will always be the last part of first line chunk
          change_chunk = split_line[0].split(/\s/).last

          new_path = Pathname(split_line[2]).freeze if split_line[2]
          old_path = Pathname(split_line[1]).freeze
          prior_path = old_path if new_path
          # new path if one exists, else existing path. new path only exists for rename and copy
          changed_path = new_path || old_path

          change_character = change_chunk[0]
          # returns 0 when a similarity percentage isn't specified by git.
          _similarity = change_chunk[1..3].to_i

          FileModification.new(
            path: changed_path,
            type: CHANGE_CHARACTERS[change_character],
            prior_path:,
            contents_reader: -> { repository.join(changed_path).read },
            prior_contents_reader: lambda {
              git!('show', "#{base_revision}:#{prior_path || changed_path}", chdir: repository)
            }
          )
        end
      end

      # @return [String] the STDOUT of the git command
      # @raise [GitError] when running the git command fails
      # @param command [String] the base git command to run
      # @param args [String...] arguments to the git command
      # @param chdir [String,Pathname] the directory to run the git command in
      def self.git!(command, *args, chdir:)
        require 'open3'
        out, err, status = Open3.capture3('git', command, *args, chdir: chdir.to_s)
        raise GitError, "Running git #{command} failed (#{status.to_s.gsub(/pid \d+\s*/, '')}):\n\n#{err}" unless status.success?

        out
      end
      private_class_method :git!
    end
  end
end
