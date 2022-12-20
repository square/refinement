# frozen_string_literal: true

RSpec.describe Refinement::Changeset do
  let(:directory_type) { described_class::FileModification::DIRECTORY_CHANGE_TYPE }

  def mod(path, type: :changed, prior_path: nil, contents: nil, prior_contents: nil)
    described_class::FileModification.new(path: Pathname(path), type: type, prior_path: prior_path && Pathname(prior_path),
                                          contents_reader: -> { contents }, prior_contents_reader: -> { prior_contents })
  end

  describe '.add_directories' do
    subject(:modifications_with_directories) { described_class.add_directories(modifications) }

    let(:modifications) { [] }

    context 'with an empty list of modifications' do
      it { is_expected.to eq [] }
    end

    context 'with modifications at the root' do
      let(:modifications) do
        [
          mod('README.md')
        ]
      end

      it 'adds the root directory' do
        expect(modifications_with_directories).to eq [
          mod('README.md'),
          mod('./', type: directory_type)
        ]
      end
    end

    context 'with nested modifications' do
      let(:modifications) do
        [
          mod('README.md'),
          mod('a/b/c/1.swift'),
          mod('a/b/d/1.swift'),
          mod('a/b/e/1.swift'),
          mod('a/b/README.md')
        ]
      end

      it 'adds intermediary directories once' do
        expect(modifications_with_directories).to eq [
          mod('README.md'),
          mod('a/b/c/1.swift'),
          mod('a/b/d/1.swift'),
          mod('a/b/e/1.swift'),
          mod('a/b/README.md'),
          mod('./', type: directory_type),
          mod('a/b/c/', type: directory_type),
          mod('a/b/', type: directory_type),
          mod('a/', type: directory_type),
          mod('a/b/d/', type: directory_type),
          mod('a/b/e/', type: directory_type)
        ]
      end
    end
  end

  describe '.parse_raw_diff' do
    subject(:modifications) { described_class.parse_raw_diff(diff, repository: repo, base_revision: base_revision) }

    let(:repo) { '/repo' }
    let(:base_revision) { 'abcde' * 8 }

    context 'with an empty diff' do
      let(:diff) { '' }

      it { is_expected.to eq [] }
    end

    context 'with a diff' do
      let(:diff) { <<-DIFF.strip_heredoc.tr("\n", "\u0000") }
        :100644 100644 bcd1234... 0123456... M\u0000file0
        :100644 100644 abcd123... 1234567... C68\u0000file1\u0000file2
        :100644 100644 abcd123... 1234567... R86\u0000file1\u0000file3
        :000000 100644 0000000... 1234567... A\u0000file4
        :100644 000000 1234567... 0000000... D\u0000file5
        :000000 000000 0000000... 0000000... U\u0000file6
      DIFF

      it {
        is_expected.to eq [
          mod('file0', type: :"was modified"),
          mod('file2', type: :"was copied", prior_path: 'file1'),
          mod('file3', type: :"was renamed", prior_path: 'file1'),
          mod('file4', type: :"was added"),
          mod('file5', type: :"was deleted"),
          mod('file6', type: :"is unmerged")
        ]
      }
    end

    context 'with a move' do
      let(:diff) { ":100644 100644 2bf1c1c 2bf1c1c R100\u0000.ruby-version\u0000.ruby-version2\u0000" }

      it {
        is_expected.to eq [
          mod('.ruby-version2', type: :"was renamed", prior_path: '.ruby-version')
        ]
      }
    end
  end

  describe '.find_modification_for_glob' do
    let(:changeset) do
      described_class.new(
        repository: '/repo',
        modifications: modifications
      )
    end
    let(:glob) { '/repo/dir/*' }
    let(:glob_modification) { changeset.find_modification_for_glob(absolute_glob: glob) }
    let(:modifications) { [] }

    context 'with two matching modifications' do
      let(:modifications) do
        [
          mod('dir/file1.txt'),
          mod('dir/file2.txt')
        ]
      end

      it 'returns any modification' do
        expect(glob_modification).not_to eq nil
        expect(modifications).to include glob_modification
      end
    end

    context 'with no matching modifications' do
      let(:modifications) do
        [
          mod('other_dir/file.txt')
        ]
      end

      it 'returns nil' do
        expect(glob_modification).to eq nil
      end
    end
  end

  describe '.find_modifications_for_glob' do
    let(:changeset) do
      described_class.new(
        repository: '/repo',
        modifications: modifications
      )
    end
    let(:glob) { '/repo/dir/*' }
    let(:glob_modifications) { changeset.find_modifications_for_glob(absolute_glob: glob) }
    let(:modifications) { [] }

    context 'with two modifications' do
      let(:modifications) do
        [
          mod('dir/file1.txt'),
          mod('dir/file2.txt')
        ]
      end

      it 'returns both modifications' do
        expect(glob_modifications).to include mod('dir/file1.txt', type: :changed)
        expect(glob_modifications).to include mod('dir/file2.txt', type: :changed)
      end

      context 'when only one matches the glob' do
        let(:glob) { '/repo/dir/file1.*' }

        it 'skips non-matching modifications' do
          expect(glob_modifications).not_to include mod('dir/file2.txt', type: :changed)
        end
      end

      context 'when not matching the glob' do
        let(:glob) { '/repo/dir/other' }

        it 'returns no modifications' do
          expect(glob_modifications).to eq []
        end
      end
    end
  end
end
