# frozen_string_literal: true

require 'spec_helper/dsl'
require 'xcodeproj'

RSpec.describe Sq::Refinement::Analyzer do
  include SpecHelper::DSL

  def self.project(&)
    let(:project) { build_project(&) }
  end

  def self.changesets(*blks, &blk)
    raise ArgumentError, 'Provide either a list of blocks for a changeset of a single proc to yield to' if blk && !blks.empty?

    blks << blk if blk
    let(:changesets) { blks.map { |b| build_changeset(&b) } }
  end

  def self.changeset(&)
    changesets(&)
  end

  project do
    # Rubocop: shh
  end

  changeset do
    # Rubocop: shh
  end

  subject { changes(level: change_level, augmenting_paths_by_target:) }

  let(:change_level) { :itself }
  let(:augmenting_paths_by_target) { {} }

  context 'with no changes' do
    project do
      target 'foo' do
        # Rubocop: shh
      end
    end
    it { is_expected.to eq 'foo' => nil }
  end

  context 'with a change to a file in the target' do
    project do
      foo = target 'foo' do
        source_files 'a.swift', 'b.swift'
      end

      bar = target 'bar' do
        add_dependency foo
      end

      target 'baz' do
        add_dependency bar
      end
    end

    changeset do
      file 'a.swift'
    end

    it { is_expected.to eq 'bar' => nil, 'foo' => 'a.swift (source file) changed', 'baz' => nil }

    context 'when multiple files are changed' do
      changeset do
        file 'a.swift'
        file 'b.swift'
        file 'c.swift'
      end
      it { is_expected.to eq 'bar' => nil, 'foo' => 'a.swift (source file) changed', 'baz' => nil }
    end

    context 'with full transitive mode' do
      let(:change_level) { :full_transitive }

      it { is_expected.to eq 'bar' => 'dependency foo changed because a.swift (source file) changed', 'foo' => 'a.swift (source file) changed', 'baz' => 'dependency bar changed because dependency foo changed because a.swift (source file) changed' }
    end

    context 'with at_most_n_away mode and n = 1' do
      let(:change_level) { [:at_most_n_away, 1] }

      it { is_expected.to eq 'bar' => 'dependency foo changed because a.swift (source file) changed', 'foo' => 'a.swift (source file) changed', 'baz' => nil }
    end

    context 'with at_most_n_away mode and n = 2' do
      let(:change_level) { [:at_most_n_away, 2] }

      it { is_expected.to eq 'bar' => 'dependency foo changed because a.swift (source file) changed', 'foo' => 'a.swift (source file) changed', 'baz' => 'dependency bar changed because dependency foo changed because a.swift (source file) changed' }
    end

    context 'with at_most_n_away mode and n = 99' do
      let(:change_level) { [:at_most_n_away, 99] }

      it { is_expected.to eq 'bar' => 'dependency foo changed because a.swift (source file) changed', 'foo' => 'a.swift (source file) changed', 'baz' => 'dependency bar changed because dependency foo changed because a.swift (source file) changed' }
    end
  end

  context 'when the project is changed' do
    project { target 'foo' }
    changeset do
      file 'project.xcodeproj/project.pbxproj'
    end

    it { is_expected.to eq 'foo' => 'project.xcodeproj/ (project directory) had contents change' }

    context 'when in a nested directory' do
      changeset do
        file 'project.xcodeproj/xcshareddata/xcshemes/foo.xcscheme'
      end
      it { is_expected.to eq 'foo' => 'project.xcodeproj/ (project directory) had contents change' }
    end
  end

  context 'when an INFOPLIST_FILE changes' do
    project do
      target 'foo' do
        build_settings 'INFOPLIST_FILE' => 'foo-Info.plist'
      end
    end
    changeset do
      file 'foo-Info.plist'
    end

    it { is_expected.to eq 'foo' => 'foo-Info.plist (INFOPLIST_FILE value) changed' }
  end

  context 'when a file in HEADER_SEARCH_PATHS changes' do
    project do
      target 'foo' do
        build_settings 'HEADER_SEARCH_PATHS' => %w[include]
      end
    end
    changeset do
      file 'include/errors.h'
    end

    it { is_expected.to eq 'foo' => 'include/ (HEADER_SEARCH_PATHS value) had contents change' }
  end

  context 'when a file in a directory that matches a random build setting changes' do
    project do
      target 'foo' do
        build_settings 'abcdefg' => 'abcdefg'
      end
    end
    changeset do
      file 'abcdefg/hijklmnop.txt'
    end

    it { is_expected.to eq 'foo' => nil }
  end

  context 'when a file used by multiple targets changes' do
    project do
      target 'foo' do
        source_files 'common.m'
      end
      target 'bar' do
        source_files 'common.m'
      end
    end

    changeset do
      file 'common.m'
      file 'common.h', type: 'D' # not used by any target, should not show up
    end

    it { is_expected.to eq 'foo' => 'common.m (source file) changed', 'bar' => 'common.m (source file) changed' }
  end

  describe 'with multiple changesets' do
    context 'when different dependencies change' do
      project do
        foo = target 'foo' do
          source_files 'foo.m'
        end
        bar = target 'bar' do
          source_files 'bar.m'
        end
        target 'baz' do
          source_files 'baz.m'
          add_dependency foo
          add_dependency bar
        end
      end

      changesets(
        ->(*) { file 'foo.m' },
        ->(*) { file 'bar.m' }
      )

      it { is_expected.to eq 'foo' => nil, 'bar' => nil, 'baz' => nil }
    end

    context 'when different dependencies & target change' do
      project do
        foo = target 'foo' do
          source_files 'foo.m'
        end
        bar = target 'bar' do
          source_files 'bar.m'
        end
        target 'baz' do
          source_files 'baz.m'
          add_dependency foo
          add_dependency bar
        end
      end

      changesets(
        ->(*) { file 'foo.m' },
        ->(*) { file 'bar.m' },
        lambda { |*|
          file 'baz.m'
          self.description = 'change with baz'
        }
      )

      it { is_expected.to eq 'foo' => nil, 'bar' => nil, 'baz' => nil }
    end

    context 'when second change adds a new changed file' do
      project do
        foo = target 'foo' do
          source_files 'foo.m'
        end
        bar = target 'bar' do
          source_files 'bar.m'
        end
        target 'baz' do
          source_files 'baz.m'
          add_dependency foo
          add_dependency bar
        end
      end

      changesets(
        lambda { |*|
          file 'foo.m'
          self.description = 'original change'
        },
        lambda { |*|
          file 'bar.m'
          file 'foo.m'
          self.description = 'second change'
        }
      )

      it { is_expected.to eq 'foo' => 'foo.m (source file) changed (second change)', 'bar' => nil, 'baz' => nil }

      context 'with full_transitive changes' do
        let(:change_level) { :full_transitive }

        it { is_expected.to eq 'foo' => 'foo.m (source file) changed (second change)', 'bar' => nil, 'baz' => 'dependency foo changed because foo.m (source file) changed (second change)' }
      end
    end
  end

  context 'with augmenting_paths_by_target' do
    project do
      target 'foo' do
        source_files 'main.m'
      end
      target 'bar' do
        source_files 'main.swift'
      end
    end

    let(:augmenting_paths_by_target) do
      {
        'foo' => [
          { 'path' => 'README.md', 'inclusion_reason' => 'READMEs are important' }
        ],
        'bar' => [
          { 'glob' => '**/*.md', 'inclusion_reason' => 'documentation is key' }
        ]
      }
    end

    changeset do
      file 'README.md'
    end

    it { is_expected.to eq 'foo' => 'README.md (READMEs are important) changed', 'bar' => 'README.md (documentation is key) changed' }
  end

  context 'with augmenting_paths_by_target that affect all targets' do
    project do
      target 'foo'
      target 'bar'
    end

    let(:augmenting_paths_by_target) do
      {
        '*' => [
          { 'path' => 'Gemfile.lock', 'inclusion_reason' => 'ruby dependencies' }
        ]
      }
    end

    changeset do
      file 'Gemfile.lock'
    end

    it { is_expected.to eq 'foo' => 'Gemfile.lock (ruby dependencies) changed', 'bar' => 'Gemfile.lock (ruby dependencies) changed' }
  end

  context 'with augmenting_paths_by_target that reference directories' do
    project do
      target 'foo'
      target 'bar'
    end

    let(:augmenting_paths_by_target) do
      {
        'foo' => [
          { 'path' => 'a', 'inclusion_reason' => 'dir a' }
        ],
        'bar' => [
          { 'path' => 'b/', 'inclusion_reason' => 'dir b' }
        ]
      }
    end

    changeset do
      file 'a/a.txt'
      file 'b/b.txt'
    end

    it { is_expected.to eq 'foo' => 'a/ (dir a) had contents change', 'bar' => 'b/ (dir b) had contents change' }
  end

  context 'with augmenting_paths_by_target using YAML keypaths' do
    project do
      target 'foo'
      target 'bar'
      target 'baz'
    end

    let(:augmenting_paths_by_target) do
      {
        'foo' => [
          { 'path' => 'metadata.yaml', 'yaml_keypath' => %w[foo], 'inclusion_reason' => 'target metadata' }
        ],
        'bar' => [
          { 'path' => 'metadata.yaml', 'yaml_keypath' => %w[bar], 'inclusion_reason' => 'target metadata' }
        ],
        'baz' => [
          { 'path' => 'metadata.yaml', 'yaml_keypath' => %w[], 'inclusion_reason' => 'target metadata' }
        ]
      }
    end

    changeset do
      file 'metadata.yaml',
           current_content: "---\nfoo: a\nbar: b\nbaz: c\n",
           prior_content: "---\nfoo: a\nbar: BB\nbaz: c\n"
    end

    it { is_expected.to eq 'foo' => nil, 'bar' => 'metadata.yaml @ bar (target metadata) changed', 'baz' => 'metadata.yaml (target metadata) changed' }
  end

  context 'with a target that depends on another target via auto-linking' do
    let(:change_level) { :full_transitive }

    project do
      target 'foo_framework', type: :framework do
        source_files 'main.swift'
        product_reference.path = 'foo.framework'
      end
      target 'foo_framework_with_name_and_different_path', type: :framework do
        source_files 'main.swift'
        product_reference.path = 'foo-framework-with-name.framework'
        product_reference.name = 'foo_framework_with_name.framework'
      end
      target 'foo_static_library', type: :library do
        source_files 'main.swift'
        product_reference.path = 'libFoo.a'
      end
      target 'foo_dynamic_library', type: :dynamic_library do
        source_files 'main.swift'
        product_reference.path = 'libFoo.dylib'
      end
      target 'bar' do
        frameworks_build_phases.add_file_reference(project.new_file('foo.framework'))
      end
      target 'baz' do
        frameworks_build_phases.add_file_reference(project.new_file('libFoo.a'))
      end
      target 'qux' do
        frameworks_build_phases.add_file_reference(project.new_file('libFoo.dylib'))
      end
      target 'quux' do
        frameworks_build_phases.add_file_reference(project.new_file('foo_framework_with_name.framework'))
      end
    end

    changeset do
      file 'main.swift'
    end
    it {
      is_expected.to eq 'bar' => 'dependency foo_framework changed because main.swift (source file) changed',
                        'baz' => 'dependency foo_static_library changed because main.swift (source file) changed',
                        'foo_dynamic_library' => 'main.swift (source file) changed',
                        'foo_framework' => 'main.swift (source file) changed',
                        'foo_framework_with_name_and_different_path' => 'main.swift (source file) changed',
                        'foo_static_library' => 'main.swift (source file) changed',
                        'qux' => 'dependency foo_dynamic_library changed because main.swift (source file) changed',
                        'quux' => 'dependency foo_framework_with_name_and_different_path changed because main.swift (source file) changed'
    }
  end

  describe '#filtered_scheme' do
    subject(:filtered_scheme_to_s) { analyzer.filtered_scheme(scheme_path:, change_level:, filter_when_scheme_has_changed:, log_changes:, filter_scheme_for_build_action:).to_s }

    let(:analyzer) do
      described_class.new(changesets:, workspace_path: nil, projects: [project], augmenting_paths_yaml_files: nil, augmenting_paths_by_target:)
    end
    let(:scheme_path) { '/path/to/scheme.xcscheme' }
    let(:filter_when_scheme_has_changed) { false }
    let(:log_changes) { false }
    let(:filter_scheme_for_build_action) { :building }

    let(:scheme) { Xcodeproj::XCScheme.new }
    let(:scheme_contents) { scheme.to_s }

    let(:foo) { target(name: 'Foo') }
    let(:foo_unit_tests) { target(name: 'Foo-Unit-Tests') }

    let(:scheme_fixture_path) { Pathname("../../fixtures/#{self.class.name.gsub('::', '/')}.xcscheme").expand_path(__dir__) }

    before do
      # Must be done inside a block instead of with `and_yield` so the scheme can be modified
      allow(File).to receive(:open).with(scheme_path, 'r') { |&b| b.call scheme_contents } # rubocop:disable RSpec/Yield
    end

    project do
      foo = target 'Foo' do
        source_files 'a.swift'
      end

      target 'Foo-Unit-Tests' do
        source_files 'a_tests.swift'
        add_dependency foo
      end
    end

    def target(name:)
      scheme_fixture_path
      project.targets.find { |t| t.name == name }
    end

    context 'with an empty scheme' do
      it 'returns the scheme unmodified' do
        expect(filtered_scheme_to_s).to eq scheme_contents
      end
    end

    context 'when the scheme contains targets' do
      before do
        scheme.add_build_target foo
        scheme.add_test_target foo_unit_tests
        scheme.set_launch_target foo
      end

      context 'with a scheme with no modified targets' do
        it 'returns the scheme without the targets' do
          expect(filtered_scheme_to_s).to eq(scheme_fixture_path.read), "see #{scheme_fixture_path}"
        end
      end

      context 'with a scheme with a modified build target' do
        changeset { file 'a.swift' }

        it 'returns the scheme unmodified' do
          expect(filtered_scheme_to_s).to eq(scheme_fixture_path.read), "see #{scheme_fixture_path}"
        end

        context 'when filtering for testing' do
          let(:change_level) { :full_transitive }
          let(:filter_scheme_for_build_action) { :testing }

          it 'returns the modified scheme retaining the build entries' do
            expect(filtered_scheme_to_s).to eq(scheme_fixture_path.read), "see #{scheme_fixture_path}"
          end
        end

        context 'with the change level as full_transitive' do
          let(:change_level) { :full_transitive }

          it 'returns the modified scheme' do
            expect(filtered_scheme_to_s).to eq(scheme_fixture_path.read), "see #{scheme_fixture_path}"
          end
        end
      end

      context 'with a scheme with a modified test target' do
        changeset { file 'a_tests.swift' }

        it 'returns the scheme unmodified' do
          expect(filtered_scheme_to_s).to eq(scheme_fixture_path.read), "see #{scheme_fixture_path}"
        end

        context 'when filtering for testing' do
          let(:change_level) { :full_transitive }
          let(:filter_scheme_for_build_action) { :testing }

          it 'returns the modified scheme retaining the build entries' do
            expect(filtered_scheme_to_s).to eq(scheme_fixture_path.read), "see #{scheme_fixture_path}"
          end
        end

        context 'with the change level as full_transitive' do
          let(:change_level) { :full_transitive }

          it 'returns the modified scheme' do
            expect(filtered_scheme_to_s).to eq(scheme_fixture_path.read), "see #{scheme_fixture_path}"
          end
        end

        context 'with each target lambda' do
          subject!(:filtered_scheme) do
            analyzer.filtered_scheme(scheme_path:,
                                     change_level:, filter_when_scheme_has_changed:,
                                     log_changes:, filter_scheme_for_build_action:,
                                     each_target: each_target_lambda)
          end

          let(:results) { {} }
          let(:each_target_lambda) do
            lambda do |type:, target_name:, change_reason:|
              results[type] ||= []
              results[type] << "#{target_name} (#{change_reason})"
            end
          end

          it 'correctly invokes each target lambda' do
            expected = {
              unchanged: ['Foo ()'],
              changed: ['Foo-Unit-Tests (a_tests.swift (source file) changed)']
            }
            expect(results).to eq expected
          end
        end
      end
    end
  end
end
