require_relative "../spec_helper"

RSpec.describe Relaton::Render::Iso690::I18n do
  describe ".load" do
    it "keeps the requested language when the pack falls back to en" do
      expect(described_class.load("ja").lang).to eq("ja")
    end

    it "keeps the pack language when the pack exists" do
      expect(described_class.load("fr").lang).to eq("fr")
    end
  end
end
