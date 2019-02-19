RSpec.describe Refinement::AnnotatedTarget do
  subject(:annotated_target) { described_class.new(target: target, change_reason: change_reason, dependencies: dependencies) }

  let(:target) do
    instance_double(
      Xcodeproj::Project::Object::AbstractTarget, 'xcode_target',
      to_s: 'FooApp'
    )
  end
  let(:change_reason) { 'main.swift (source file) was changed' }
  let(:dependencies) { [] }

  describe '#xcode_target' do
    it 'returns the xcode target' do
      expect(annotated_target.xcode_target).to equal target
    end
  end

  describe '#to_s' do
    it "returns the xcode target's name" do
      expect(annotated_target.to_s).to eq 'FooApp'
    end
  end

  describe '#change_reason' do
    subject(:change_reason_at_level) { annotated_target.change_reason(level: level) }

    context 'when the level is :itself' do
      let(:level) { :itself }

      it 'returns the direct change reason' do
        expect(change_reason_at_level).to eq change_reason
      end
    end

    context 'when the level is :full_transitive' do
      let(:level) { :itself }

      it 'returns the direct change reason' do
        expect(change_reason_at_level).to eq change_reason
      end
    end

    context 'when the level is :at_most_n_away' do
      let(:level) { [:at_most_n_away, n] }

      context 'with n = 1' do
        let(:n) { 1 }

        it 'returns the direct change reason' do
          expect(change_reason_at_level).to eq change_reason
        end
      end
    end

    context 'when the level is :full_transitive' do
      let(:level) { :itself }

      it 'returns the direct change reason' do
        expect(change_reason_at_level).to eq change_reason
      end
    end
  end

  describe '#dependencies' do
    it 'returns the dependencies' do
      expect(annotated_target.dependencies).to equal dependencies
    end
  end

  describe '#depended_upon_by' do
    it 'returns the targets that depend upon it' do
      expect(annotated_target.depended_upon_by).to eq []
    end
  end
end
