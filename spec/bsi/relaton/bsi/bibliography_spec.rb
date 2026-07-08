# frozen_string_literal: true

describe Relaton::Bsi::Bibliography do
  describe ".parse" do
    it "parses a BSI reference into a pubid identifier" do
      expect(described_class.parse("BS EN ISO 8848:2021"))
        .to be_a ::Pubid::Bsi::Identifier
    end

    it "returns nil when pubid can't parse the reference" do
      expect(described_class.parse("BS NOT A REF !!")).to be_nil
    end
  end

  describe ".publication_year" do
    it "reads the base document's year" do
      expect(described_class.publication_year("BS EN ISO 8848:2021")).to eq "2021"
    end

    it "reads the base year of a consolidated (amendment) reference" do
      expect(described_class.publication_year("BS 7273-4:2015+A1:2021")).to eq "2015"
    end

    it "is nil for an undated reference" do
      expect(described_class.publication_year("BS 5266-1")).to be_nil
    end
  end

  describe ".same_reference?" do
    def parse(code) = described_class.parse(code)

    def same?(a, b, **opts)
      described_class.same_reference?(parse(a), parse(b), **opts)
    end

    it "matches the same designator regardless of publication year" do
      expect(same?("BS EN ISO 8848", "BS EN ISO 8848:2022")).to be true
    end

    it "rejects a different part" do
      expect(same?("BS 5266-1", "BS 5266-2")).to be false
    end

    it "treats the amendment year as optional when the query omits it" do
      expect(same?("BS EN ISO 14044:2006+A2", "BS EN ISO 14044:2006+A2:2020"))
        .to be true
    end

    it "does not match a bare reference against its amended variant" do
      expect(same?("PAS 2031:2019", "PAS 2031:2019+A1:2020")).to be false
    end

    it "matches ExComm against the Expert Commentary long form" do
      expect(same?("BS EN ISO 13485 ExComm", "BS EN ISO 13485 Expert Commentary"))
        .to be true
    end

    it "does not match a plain reference against its Expert Commentary" do
      expect(same?("BS EN ISO 13485", "BS EN ISO 13485 Expert Commentary")).to be false
    end

    it "distinguishes an amendment from a corrigendum of the same number" do
      expect(same?("BS 1234:2015+A1", "BS 1234:2015+C1")).to be false
    end

    it "ignores the Flex version only when skip_rest is set" do
      expect(same?("BSI Flex 0", "BSI Flex 0 v2.0")).to be false
      expect(same?("BSI Flex 0", "BSI Flex 0 v2.0", skip_rest: true)).to be true
    end

    it "matches base documents when drop_amd is set" do
      expect(same?("BS 7273-4", "BS 7273-4:2015+A1:2021", drop_amd: true)).to be true
    end

    it "does not match a specific-amendment query against a different amendment via drop_amd" do
      # query wants +A1; the only hit is +A2. drop_amd reduces the hit to its base,
      # but the query still carries a supplement, so it must not match.
      expect(same?("BS 7273-4:2015+A1", "BS 7273-4:2015+A2:2020", drop_amd: true))
        .to be false
    end
  end
end
