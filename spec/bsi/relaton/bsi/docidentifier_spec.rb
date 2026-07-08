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
end
