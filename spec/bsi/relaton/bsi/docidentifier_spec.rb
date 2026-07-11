# frozen_string_literal: true

describe Relaton::Bsi::Docidentifier do
  context "parses BSI codes into a Pubid::Bsi identifier" do
    it "exposes #pubid for a BSI-type identifier" do
      did = described_class.new(type: "BSI", content: "BS EN ISO 8848:2021", primary: true)
      expect(did.pubid).to be_a ::Pubid::Bsi::Identifier
    end

    # round-trip: content must remain byte-identical to the source string,
    # including forms pubid renders verbatim (amendments, ExComm, Flex version).
    [
      "BS EN ISO 8848:2021",
      "PAS 2035/2030:2019+A1:2022",
      "BS 7273-4:2015+A1:2021 ExComm",
      "BSI Flex 0 v2.0",
    ].each do |code|
      it "round-trips #{code.inspect}" do
        did = described_class.new(type: "BSI", content: code)
        expect(did.pubid).to be_a ::Pubid::Bsi::Identifier
        expect(did.content).to eq code
        expect(did.to_s).to eq code
      end
    end
  end

  context "non-BSI identifiers stay as plain strings" do
    it "does not parse an ISBN into a pubid and keeps the raw content" do
      did = described_class.new(type: "ISBN", content: "978-0-539-00000-0")
      expect(did.pubid).to be_nil
      expect(did.content).to eq "978-0-539-00000-0"
    end
  end

  describe "#remove_date!" do
    it "strips the year from a dated BSI identifier via pubid" do
      did = described_class.new(type: "BSI", content: "BS EN ISO 8848:2021")
      did.remove_date!
      expect(did.content).to eq "BS EN ISO 8848"
    end

    it "drops the base date but keeps the amendment on a consolidated id" do
      did = described_class.new(type: "BSI", content: "PAS 2035/2030:2019+A1:2022")
      did.remove_date!
      expect(did.content).to eq "PAS 2035/2030+A1:2022"
    end

    it "is a no-op for a non-BSI identifier (ISBN)" do
      did = described_class.new(type: "ISBN", content: "978-0-539-00000-0")
      did.remove_date!
      expect(did.content).to eq "978-0-539-00000-0"
    end
  end

  describe "#remove_part!" do
    it "drops the part from a parted BSI identifier via pubid" do
      did = described_class.new(type: "BSI", content: "BS 7273-4:2015")
      did.remove_part!
      expect(did.content).to eq "BS 7273:2015"
    end

    it "drops the part but keeps the amendment on a consolidated id" do
      did = described_class.new(type: "BSI", content: "BS 7273-4:2015+A1:2021")
      did.remove_part!
      expect(did.content).to eq "BS 7273:2015+A1:2021"
    end

    it "strips the part from an adopted-standard id (nested identifier)" do
      did = described_class.new(type: "BSI", content: "BS EN ISO 8848-1:2021")
      did.remove_part!
      expect(did.content).to eq "BS EN ISO 8848:2021"
    end

    it "does not change an id without a part" do
      did = described_class.new(type: "BSI", content: "BS EN ISO 8848:2021")
      did.remove_part!
      expect(did.content).to eq "BS EN ISO 8848:2021"
    end

    it "is a no-op for a non-BSI identifier (ISBN)" do
      did = described_class.new(type: "ISBN", content: "978-0-539-00000-0")
      did.remove_part!
      expect(did.content).to eq "978-0-539-00000-0"
    end

    it "is a no-op for unparseable content (nil pubid)" do
      did = described_class.new(type: "BSI", content: "not a standard at all")
      expect(did.pubid).to be_nil
      did.remove_part!
      expect(did.content).to eq "not a standard at all"
    end
  end

  describe "#to_all_parts!" do
    # BSI's pubid renderer does not emit an "(all parts)" marker (unlike ISO),
    # so the rendered content degrades to the part+date-stripped form while the
    # structural `all_parts` flag is still set on the underlying identifier.
    it "strips the part and date and sets the all_parts flag" do
      did = described_class.new(type: "BSI", content: "BS 7273-4:2015")
      did.to_all_parts!
      expect(did.content).to eq "BS 7273"
      expect(did.pubid.all_parts).to be true
    end

    it "strips part+date from an adopted-standard id and sets the flag" do
      did = described_class.new(type: "BSI", content: "BS EN ISO 8848-1:2021")
      did.to_all_parts!
      expect(did.content).to eq "BS EN ISO 8848"
      expect(did.pubid.all_parts).to be true
    end

    it "keeps the amendment while dropping part+date on a consolidated id" do
      did = described_class.new(type: "BSI", content: "BS 7273-4:2015+A1:2021")
      did.to_all_parts!
      expect(did.content).to eq "BS 7273+A1:2021"
      expect(did.pubid.all_parts).to be true
    end

    it "is a no-op for a non-BSI identifier (ISBN)" do
      did = described_class.new(type: "ISBN", content: "978-0-539-00000-0")
      did.to_all_parts!
      expect(did.content).to eq "978-0-539-00000-0"
    end

    it "is a no-op for unparseable content (nil pubid)" do
      did = described_class.new(type: "BSI", content: "not a standard at all")
      expect(did.pubid).to be_nil
      did.to_all_parts!
      expect(did.content).to eq "not a standard at all"
    end
  end
end
