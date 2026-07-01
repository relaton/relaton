# frozen_string_literal: true

RSpec.describe Relaton::Oasis::Ext do
  describe "#get_schema_version" do
    it "returns the schema version for relaton-model-oasis" do
      ext = described_class.new
      expect(ext.get_schema_version).to eq Relaton.schema_versions["relaton-model-oasis"]
    end
  end
end
