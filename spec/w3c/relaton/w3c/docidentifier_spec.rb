describe Relaton::W3c::Docidentifier do
  # `DataParser#pub_id` builds "W3C <identifier>", publisher prefix included,
  # which is exactly the form `Pubid::W3c::Identifier.parse` wants. Nothing
  # synthesizes or strips a prefix.
  describe "#content=" do
    it "parses the content into a Pubid::W3c identifier" do
      d = described_class.new(content: "W3C REC-xml-names-20091208",
                              type: "W3C", primary: true)
      expect(d.pubid).to be_a Pubid::W3c::Identifiers::Recommendation
      expect(d.pubid.number).to eq "xml-names"
      expect(d.pubid.date).to eq "20091208"
    end

    it "keeps the source string verbatim as content" do
      d = described_class.new(content: "W3C REC-xml-names-20091208", type: "W3C")
      expect(d.content).to eq "W3C REC-xml-names-20091208"
    end

    it "parses a bare slug as the Standard leaf" do
      d = described_class.new(content: "W3C xml-names", type: "W3C")
      expect(d.pubid).to be_a Pubid::W3c::Identifiers::Standard
      expect(d.pubid.number).to eq "xml-names"
    end

    it "leaves pubid nil when there is no content" do
      expect(described_class.new(type: "W3C").pubid).to be_nil
    end

    # An identifier that does not parse is a data defect, so it is reported at
    # ERROR — never WARN. It must not raise: an already-published record still
    # has to deserialize and render. The crawl turns the same failure into a
    # tracked GitHub issue via `report_errors`.
    context "when the content does not parse" do
      it "logs at ERROR and leaves pubid nil, without raising" do
        d = nil
        expect do
          d = described_class.new(content: "not a W3C ref at all", type: "W3C")
        end.to output(/\[relaton-w3c\] ERROR.*Failed to parse pubid/)
          .to_stderr_from_any_process
        expect(d.pubid).to be_nil
      end

      it "still keeps the content" do
        d = nil
        expect do
          d = described_class.new(content: "not a W3C ref at all", type: "W3C")
        end.to output.to_stderr_from_any_process
        expect(d.content).to eq "not a W3C ref at all"
      end
    end
  end

  describe "round-trip via Relaton::W3c::Bibdata" do
    let(:xml) do
      <<~XML
        <bibdata type="standard" schema-version="v1.5.6">
          <docidentifier type="W3C" primary="true">W3C REC-xml-names-20091208</docidentifier>
          <ext schema-version="v1.0.0">
            <doctype>recommendation</doctype>
            <flavor>w3c</flavor>
          </ext>
        </bibdata>
      XML
    end

    it "deserializes the docidentifier with a parsed pubid" do
      docid = Relaton::W3c::Bibdata.from_xml(xml).docidentifier.first
      expect(docid).to be_a described_class
      expect(docid.pubid.number).to eq "xml-names"
    end

    it "round-trips back to equivalent XML" do
      item = Relaton::W3c::Bibdata.from_xml(xml)
      expect(Relaton::W3c::Bibdata.to_xml(item)).to be_equivalent_to xml
    end
  end
end
