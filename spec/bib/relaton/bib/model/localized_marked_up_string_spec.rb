# frozen_string_literal: true

RSpec.describe Relaton::Bib::LocalizedMarkedUpString do
  describe ".cast (lutaml-model#972)" do
    it "wraps a bare scalar so a singular custom-typed attribute serializes" do
      relation = Relaton::Bib::Relation.new(description: "Test description text")
      yaml = relation.to_yaml
      expect(yaml).to include("Test description text")
      round = Relaton::Bib::Relation.from_yaml(yaml)
      expect(round.description).to be_instance_of(described_class)
      expect(round.description.content).to eq "Test description text"
    end

    it "keeps an existing instance untouched" do
      value = described_class.new(content: "Marked up")
      expect(described_class.cast(value)).to equal(value)
    end
  end
end
