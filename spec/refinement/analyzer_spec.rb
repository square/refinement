require 'spec_helper/dsl'

RSpec.describe Refinement::Analyzer do
  include SpecHelper::DSL

  def self.project(&blk)
    let(:project) { build_project(&blk) }
  end

  def self.changeset(&blk)
    let(:changeset) { build_changeset(&blk) }
  end

  project {}
  changeset {}
  subject { changes(level: change_level, augmenting_paths_by_target: augmenting_paths_by_target) }

  let(:change_level) { :itself }
  let(:augmenting_paths_by_target) { {} }

  context 'with no changes' do
    project do
      target 'foo' do
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

    context ' when in a nested directory' do
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
    end

    changeset do
      file 'main.swift'
    end
    it {
      is_expected.to eq 'bar' => 'dependency foo_framework changed because main.swift (source file) changed',
                        'baz' => 'dependency foo_static_library changed because main.swift (source file) changed',
                        'foo_dynamic_library' => 'main.swift (source file) changed',
                        'foo_framework' => 'main.swift (source file) changed',
                        'foo_static_library' => 'main.swift (source file) changed',
                        'qux' => 'dependency foo_dynamic_library changed because main.swift (source file) changed'
    }
  end
end
