# frozen_string_literal: true

describe Relaton::Etsi do
  describe "#grammar_hash" do
    it "returns MD5 hash of version strings" do
      result = described_class.grammar_hash
      expected = Digest::MD5.hexdigest(
        Relaton::Etsi::VERSION + Relaton::Bib::VERSION
      )

      expect(result).to eq expected
      expect(result).to match(/\A[a-f0-9]{32}\z/)
    end
  end
end
