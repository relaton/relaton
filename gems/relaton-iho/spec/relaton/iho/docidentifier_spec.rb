describe Relaton::Iho::Docidentifier do
  describe "#initialize" do
    it "parses content into a Pubid::Identifier" do
      d = described_class.new(content: "S-100 Part 1", type: "IHO", primary: true)
      expect(d.pubid).to be_a Pubid::Identifier
      expect(d.pubid.number).to eq "100"
      expect(d.pubid.part).to eq "1"
      expect(d.content).to eq "S-100 Part 1"
    end

    it "accepts a parsed Pubid object via :pubid keyword" do
      pubid = Pubid::Iho::Identifier.parse("IHO S-4")
      d = described_class.new(pubid: pubid, type: "IHO", primary: true)
      expect(d.pubid).to equal pubid
      expect(d.content).to eq "IHO S-4"
    end

    it "raises StandardError on bad input (hard error)" do
      expect { described_class.new(content: "not a real ref", type: "IHO") }
        .to raise_error(StandardError)
    end

    it "leaves @pubid nil when content is empty" do
      d = described_class.new(type: "IHO")
      expect(d.pubid).to be_nil
    end
  end

  describe "#remove_part!" do
    it "clears part on the underlying Pubid identifier" do
      d = described_class.new(content: "S-100 Part 1", type: "IHO", primary: true)
      expect(d.pubid.part).to eq "1"
      d.remove_part!
      expect(d.pubid.part).to be_nil
    end

    it "is a safe no-op when pubid is nil" do
      d = described_class.new(type: "IHO")
      expect { d.remove_part! }.not_to raise_error
      expect(d.pubid).to be_nil
    end
  end

  describe "#remove_date!" do
    it "clears year on the underlying Pubid identifier" do
      d = described_class.new(content: "S-100 Part 1", type: "IHO", primary: true)
      d.pubid.date = Pubid::Components::Date.new(year: "2020")
      d.remove_date!
      expect(d.pubid.date).to be_nil
    end

    it "is a safe no-op when pubid is nil" do
      d = described_class.new(type: "IHO")
      expect { d.remove_date! }.not_to raise_error
      expect(d.pubid).to be_nil
    end
  end

  describe "#to_all_parts!" do
    it "marks the underlying Pubid identifier as covering all parts" do
      d = described_class.new(content: "S-100 Part 1", type: "IHO", primary: true)
      expect(d.pubid.all_parts).to be_falsey
      d.to_all_parts!
      expect(d.pubid.all_parts).to be true
    end

    it "is a safe no-op when pubid is nil" do
      d = described_class.new(type: "IHO")
      expect { d.to_all_parts! }.not_to raise_error
      expect(d.pubid).to be_nil
    end
  end

  describe "round-trip via Iho::Item" do
    let(:xml) do
      <<~XML
        <bibdata type="standard" schema-version="v1.5.6">
          <docidentifier type="IHO" primary="true">S-100 Part 1</docidentifier>
          <ext schema-version="v1.1.2">
            <doctype>standard</doctype>
            <flavor>iho</flavor>
          </ext>
        </bibdata>
      XML
    end

    it "deserialises docidentifier as Iho::Docidentifier with parsed Pubid" do
      item = Relaton::Iho::Bibdata.from_xml(xml)
      docid = item.docidentifier.first
      expect(docid).to be_a described_class
      expect(docid.pubid).to be_a Pubid::Identifier
      expect(docid.pubid.part).to eq "1"
    end

    it "round-trips back to equivalent XML" do
      item = Relaton::Iho::Bibdata.from_xml(xml)
      out = Relaton::Iho::Bibdata.to_xml(item)
      expect(out).to be_equivalent_to xml
    end

    it "raises on non-parseable docidentifier in incoming XML" do
      bad_xml = xml.sub("S-100 Part 1", "garbage ref")
      expect { Relaton::Iho::Bibdata.from_xml(bad_xml) }
        .to raise_error(StandardError)
    end
  end

  describe "Bibliography uses Pubid for input parsing" do
    it "parses IHO B-11 via Pubid", vcr: "b_11" do
      result = Relaton::Iho::Bibliography.search "IHO B-11"
      docid = result.docidentifier.first
      expect(docid).to be_a described_class
      expect(docid.pubid.number).to eq "11"
    end

    it "auto-populates ext.structuredidentifier when fetched record lacks one",
       vcr: "s_4" do
      result = Relaton::Iho::Bibliography.get "IHO S-4"
      sid = result.ext.structuredidentifier.first
      expect(sid).to be_a Relaton::Iho::StructuredIdentifier
      expect(sid.docnumber).to eq "S-4"
    end
  end
end
