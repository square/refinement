# frozen_string_literal: true

RSpec.describe Refinement::UsedPath do
  subject(:used_path) { described_class.new(path: path, inclusion_reason: inclusion_reason) }

  let(:path) { Pathname('/repo/main.swift') }
  let(:inclusion_reason) { 'super important file' }

  describe '#find_in_changeset' do
    subject(:change_reason) { used_path.find_in_changeset(changeset) }

    context 'when the changeset does not contain the path' do
      let(:changeset) do
        Refinement::Changeset.new(repository: Pathname('/repo'), modifications: [])
      end

      it 'returns a nil change reason' do
        expect(change_reason).to be_nil
      end
    end

    context 'when the changeset contains the path' do
      let(:changeset) do
        Refinement::Changeset.new(repository: Pathname('/repo'), modifications: [
                                    Refinement::Changeset::FileModification.new(path: Pathname('main.swift'), type: :'was changed')
                                  ])
      end

      it 'returns the change reason' do
        expect(change_reason).to eq 'main.swift (super important file) was changed'
      end
    end
  end

  describe '#to_s' do
    subject(:to_s) { used_path.to_s }

    it { is_expected.to eq '"/repo/main.swift" (super important file)' }
  end

  describe described_class::YAML do
    subject(:used_yaml_path) { described_class.new(path: path, inclusion_reason: inclusion_reason, yaml_keypath: yaml_keypath) }

    let(:yaml_keypath) { %w[keypath a b c] }

    describe '#find_in_changeset' do
      subject(:change_reason) { used_yaml_path.find_in_changeset(changeset) }

      context 'when the changeset does not contain the path' do
        let(:changeset) do
          Refinement::Changeset.new(repository: Pathname('/repo'), modifications: [])
        end

        it 'returns a nil change reason' do
          expect(change_reason).to be_nil
        end
      end

      context 'when the changeset contains the path' do
        let(:changeset) do
          Refinement::Changeset.new(repository: Pathname('/repo'), modifications: [
                                      Refinement::Changeset::FileModification.new(path: Pathname('main.swift'), type: :'was changed',
                                                                                  prior_contents_reader: -> { 'keypath: { a: { b: { c: e } } }' },
                                                                                  contents_reader: -> { 'keypath: { a: { b: { c: d } } }' })
                                    ])
        end

        it 'returns the change reason' do
          expect(change_reason).to eq 'main.swift @ keypath.a.b.c (super important file) was changed'
        end
      end
    end

    describe '#to_s' do
      subject(:to_s) { used_yaml_path.to_s }

      it { is_expected.to eq '"/repo/main.swift" @ keypath.a.b.c (super important file)' }
    end
  end

  describe Refinement::UsedGlob do
    subject(:used_glob) { described_class.new(glob: glob, inclusion_reason: inclusion_reason) }

    let(:glob) { '/repo/**/*.swift' }
    let(:inclusion_reason) { 'super important file' }

    describe '#find_in_changeset' do
      subject(:change_reason) { used_glob.find_in_changeset(changeset) }

      context 'when the changeset does not contain the path' do
        let(:changeset) do
          Refinement::Changeset.new(repository: Pathname('/repo'), modifications: [])
        end

        it 'returns a nil change reason' do
          expect(change_reason).to be_nil
        end
      end

      context 'when the changeset contains the path' do
        let(:changeset) do
          Refinement::Changeset.new(repository: Pathname('/repo'), modifications: [
                                      Refinement::Changeset::FileModification.new(path: Pathname('main.swift'), type: :'was changed')
                                    ])
        end

        it 'returns the change reason' do
          expect(change_reason).to eq 'main.swift (super important file) was changed'
        end
      end
    end

    describe '#to_s' do
      subject(:to_s) { used_glob.to_s }

      it { is_expected.to eq '"/repo/**/*.swift" (super important file)' }
    end
  end
end
