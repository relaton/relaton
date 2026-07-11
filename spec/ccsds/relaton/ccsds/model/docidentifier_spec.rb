describe Relaton::Ccsds::Docidentifier do
  subject(:docid) do
    described_class.new(content: content, type: "CCSDS", primary: true)
  end

  context "with a parseable CCSDS identifier" do
    let(:content) { "CCSDS 121.0-B-3" }

    it "parses the content into a Pubid::Ccsds::Identifier" do
      expect(docid.pubid).to be_a(::Pubid::Ccsds::Identifier)
    end

    it "round-trips the canonical string via #content and #to_s" do
      expect(docid.content).to eq "CCSDS 121.0-B-3"
      expect(docid.to_s).to eq "CCSDS 121.0-B-3"
    end

    describe "#remove_part!" do
      it "drops the part and refreshes the serialized content" do
        docid.remove_part!
        expect(docid.pubid.part).to be_nil
        expect(docid.content).to eq "CCSDS 121-B-3"
      end
    end

    describe "#remove_date!" do
      it "does not raise and leaves the (dateless) CCSDS id unchanged" do
        expect { docid.remove_date! }.not_to raise_error
        expect(docid.content).to eq "CCSDS 121.0-B-3"
      end
    end

    describe "#to_all_parts!" do
      it "drops the part and marks the pubid all_parts without raising" do
        expect { docid.to_all_parts! }.not_to raise_error
        expect(docid.pubid.part).to be_nil
        expect(docid.pubid.all_parts).to be true
        expect(docid.content).to eq "CCSDS 121-B-3"
      end
    end
  end

  context "with a translated CCSDS identifier" do
    let(:content) { "CCSDS 123.0-B-1 - Russian Translated" }

    it "round-trips the language form" do
      expect(docid.pubid).to be_a(::Pubid::Ccsds::Identifier)
      expect(docid.content).to eq "CCSDS 123.0-B-1 - Russian Translated"
    end
  end

  context "with an unparseable identifier" do
    let(:content) { "not a ccsds id" }

    it "falls back to the raw string without raising" do
      expect { docid }.not_to raise_error
      expect(docid.pubid).to be_nil
      expect(docid.content).to eq "not a ccsds id"
    end
  end

  context "round trip through the CCSDS item model" do
    let(:xml) { File.read "fixtures/ccsds_230_2-g-1.xml", encoding: "UTF-8" }
    let(:item) { Relaton::Ccsds::Bibitem.from_xml xml }

    it "deserializes the docidentifier as a Ccsds::Docidentifier" do
      docid = item.docidentifier.first
      expect(docid).to be_a(described_class)
      expect(docid.content).to eq "CCSDS 230.2-G-1"
      expect(docid).to respond_to(:remove_part!, :to_all_parts!, :remove_date!)
    end
  end
end
