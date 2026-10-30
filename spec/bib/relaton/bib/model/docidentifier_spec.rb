describe Relaton::Bib::Docidentifier do
  # `Bib::ItemData#to_all_parts` / `#to_most_recent_reference` broadcast these
  # to every docidentifier unconditionally. They used to raise
  # NotImplementedError here, which made both calls unusable for the 13 flavors
  # that never subclassed this class. The default is now a no-op; a flavor
  # whose identifier carries a part or a date overrides it (see
  # Relaton::Ogc::Docidentifier).
  subject(:docid) { described_class.new(content: "ABC 123", type: "ABC") }

  it "no-ops instead of raising" do
    expect { docid.remove_part! }.not_to raise_error
    expect { docid.to_all_parts! }.not_to raise_error
    expect { docid.remove_date! }.not_to raise_error
  end

  it "leaves the content unchanged" do
    docid.remove_part!
    docid.to_all_parts!
    docid.remove_date!
    expect(docid.content).to eq "ABC 123"
  end

  describe "#to_s" do
    def build(content, type)
      described_class.new(content: content, type: type, primary: true)
    end

    it "returns the content" do
      expect(docid.to_s).to eq "ABC 123"
    end

    it "returns an empty string for no content" do
      expect(described_class.new(type: "ABC").to_s).to eq ""
    end

    def forms(content, type)
      docid = build(content, type)
      [docid.to_s, docid.to_s(form: :external), docid.to_s(form: :internal)]
    end

    it "returns the content in both forms when the type is not in the table" do
      expect(forms("ISO/IEC 27001:2022", "ISO")).to eq ["ISO/IEC 27001:2022"] * 3
    end

    it "drops the publisher in the internal form" do
      expect(forms("BIPM SI Brochure Part 1", "BIPM"))
        .to eq ["BIPM SI Brochure Part 1", "BIPM SI Brochure Part 1", "SI Brochure Part 1"]
      expect(forms("NIST SP 800-113", "NIST"))
        .to eq ["NIST SP 800-113", "NIST SP 800-113", "SP 800-113"]
    end

    it "adds the publisher in the external form" do
      expect(forms("RFC 8341", "IETF")).to eq ["RFC 8341", "IETF RFC 8341", "RFC 8341"]
      expect(forms("draft-ietf-netconf-x-01", "Internet-Draft")).to eq [
        "draft-ietf-netconf-x-01", "IETF Internet-Draft draft-ietf-netconf-x-01",
        "Internet-Draft draft-ietf-netconf-x-01"
      ]
      expect(forms("PAS 2031:2019", "BSI")).to eq ["PAS 2031:2019", "BSI PAS 2031:2019", "PAS 2031:2019"]
    end

    it "keeps an identifier whose SDO does not take a publisher token" do
      expect(forms("CGPM RES (1889)", "BIPM")).to eq ["CGPM RES (1889)"] * 3
      expect(forms("BS EN ISO 8848:2021", "BSI")).to eq ["BS EN ISO 8848:2021"] * 3
    end

    it "returns the content when pubid cannot parse it" do
      expect(forms("BIPM not an identifier", "BIPM")).to eq ["BIPM not an identifier"] * 3
    end

    it "accepts the form as a String" do
      expect(build("NIST SP 800-113", "NIST").to_s(form: "internal")).to eq "SP 800-113"
    end

    it "raises ArgumentError for an unknown form" do
      expect { docid.to_s(form: :short) }.to raise_error ArgumentError, /short/
    end
  end
end
