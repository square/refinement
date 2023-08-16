# frozen_string_literal: true

RSpec.describe Sq::Refinement::Changeset::FileModification do
  subject(:file_modification) { described_class.new(path:, type:, prior_path:, contents_reader:, prior_contents_reader:) }

  let(:path) { '/file.m' }
  let(:type) { 'was changed' }
  let(:prior_path) { nil }
  let(:contents_reader) { -> { '// foo' } }
  let(:prior_contents_reader) { -> { '// bar' } }

  describe '#inspect' do
    subject(:inspect) { file_modification.inspect }

    it { is_expected.to eq %(#<#{described_class} path="/file.m" type="was changed" prior_path=nil contents="// foo" prior_contents="// bar">) }
  end

  describe '#to_s' do
    subject { file_modification.to_s }

    it { is_expected.to eq 'file `/file.m` was changed' }

    context 'with a prior path' do
      let(:prior_path) { '/file.mm' }

      it { is_expected.to eq 'file `/file.m` was changed (from /file.mm)' }
    end
  end

  # rubocop:disable RSpec/IdenticalEqualityAssertion
  describe '#==' do
    let(:other) { described_class.new(path: '/file.mm', type: 'was changes') }

    it 'returns false for different objects' do
      expect(file_modification).not_to eq other
      expect(other).not_to eq file_modification
    end

    it 'returns true for the same object' do
      expect(file_modification).to eq file_modification
    end
  end

  describe '#eql?' do
    let(:other) { described_class.new(path: '/file.mm', type: 'was changes') }

    it 'returns false for different objects' do
      expect(file_modification).not_to eql other
      expect(other).not_to eql file_modification
    end

    it 'returns true for the same object' do
      expect(file_modification).to eql file_modification
    end
  end
  # rubocop:enable RSpec/IdenticalEqualityAssertion

  describe '#yaml_diff' do
    subject(:yaml_diff) { file_modification.yaml_diff(keypath) }

    let(:contents) { "'abcd'" }
    let(:prior_contents) { "'abcd'" }

    let(:contents_reader) { -> { contents } }
    let(:prior_contents_reader) { -> { prior_contents } }

    let(:keypath) { [] }

    it 'returns nil when the documents are the same' do
      expect(yaml_diff).to be_nil
    end

    context 'with nested documents' do
      let(:contents) { <<-YAML.strip_heredoc }
        ---
        a: bc
        d:
          - e
          - f
          - g
        h:
          i:
            j: k
            l: [m, n, o, p]
      YAML

      context 'when the documents are the same' do
        let(:prior_contents) { contents }

        it { is_expected.to be_nil }

        context 'when the keypath is non-empty' do
          let(:keypath) { %w[h i l] << 3 }

          it { is_expected.to be_nil }
        end
      end

      context 'when the documents differ' do
        let(:prior_contents) { <<-YAML.strip_heredoc }
          ---
          a: bbcc
          d:
            - e
            - f
            - g
          h:
            i:
              j: k
              l: [mm, nn, oo, pp]
        YAML

        it { is_expected.to eq <<-YAML.strip_heredoc }
          /file.m changed at keypath []
          ---
          a:
            prior_revision: bbcc
            current_revision: bc
          h:
            i:
              l:
                prior_revision:
                - mm
                - nn
                - oo
                - pp
                current_revision:
                - m
                - "n"
                - o
                - p
        YAML

        context 'when the keypath is non-empty' do
          let(:keypath) { %w[h i l] << 3 }

          it { is_expected.to eq <<-YAML.strip_heredoc }
            /file.m changed at keypath ["h", "i", "l", 3]
            ---
            prior_revision: pp
            current_revision: p
          YAML
        end
      end
    end
  end

  shared_context 'with contents' do
    let(:dne) { described_class.const_get(:DOES_NOT_EXIST) }

    context 'when the reader returns nil' do
      let(:reader) { -> {} }

      it 'returns DOES_NOT_EXIST' do
        expect(contents).to equal dne
      end
    end

    context 'when the reader raises an exception' do
      let(:reader) { -> { File.read('/fdshjklfdshjfkdhsjfkdhsjfksd') } }

      it 'returns DOES_NOT_EXIST' do
        expect(contents).to equal dne
      end
    end

    context 'when the reader returns a string' do
      let(:reader) { -> { 'abcd' } }

      it 'returns the string' do
        expect(contents).to eq 'abcd'
      end
    end
  end

  describe '#contents' do
    subject(:contents) { file_modification.contents }

    let(:contents_reader) { reader }

    include_examples 'with contents'
  end

  describe '#prior_contents' do
    subject(:contents) { file_modification.prior_contents }

    let(:prior_contents_reader) { reader }

    include_examples 'with contents'
  end
end
