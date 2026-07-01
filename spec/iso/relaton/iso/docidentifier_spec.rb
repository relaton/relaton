describe Relaton::Iso::Docidentifier do
  subject { described_class.new content: id, type: type }

  context "PRF" do
    let(:id) { "ISO/PRF TR 17716.2(E)" }

    context "ISO" do
      let(:type) { "ISO" }
      it "should render PRF identifier" do
        expect(subject.to_s).to eq "ISO/PRF TR 17716.2"
      end
    end

    context "iso-reference" do
      let(:type) { "iso-reference" }
      it "should render PRF identifier" do
        expect(subject.to_s).to eq "ISO/PRF TR 17716.2(E)"
      end
    end

    context "iso-with-lang" do
      let(:type) { "iso-with-lang" }
      it "should render PRF identifier" do
        expect(subject.to_s).to eq "ISO/PRF TR 17716.2(E)"
      end
    end

    context "URN" do
      let(:type) { "URN" }
      it "should render PRF identifier" do
        expect(subject.to_s).to eq "urn:iso:std:iso:tr:17716:stage-draft.v2:en"
      end
    end
  end

  context "iso-tc" do
    let(:id) { "17301" }
    let(:type) { "iso-tc" }

    it "should not add ISO prefix" do
      expect(subject.to_s).to eq "17301"
    end

    it "preserves content as plain string" do
      expect(subject.content).to be_a String
    end

    it "round-trips through XML without ISO prefix" do
      xml = subject.to_xml
      expect(xml).to include("17301")
      expect(xml).not_to include("ISO 17301")
    end

    it "round-trips iso-tc through Item.from_xml without ISO prefix" do
      xml = <<~XML
        <bibdata type="standard">
          <docidentifier type="ISO" primary="true">ISO 17301-1:2016</docidentifier>
          <docidentifier type="iso-tc">17301</docidentifier>
        </bibdata>
      XML
      item = Relaton::Iso::Item.from_xml(xml)
      tc_id = item.docidentifier.find { |d| d.type == "iso-tc" }
      expect(tc_id.to_s).to eq "17301"
      roundtrip_xml = item.to_xml(bibdata: true)
      expect(roundtrip_xml).to include(">17301<")
      expect(roundtrip_xml).not_to include(">ISO 17301<")
    end

    it "preserves complex TC identifier through XML round-trip" do
      xml = <<~XML
        <bibdata type="standard">
          <docidentifier type="iso-tc">ISO/TC 184/SC 4 N1110</docidentifier>
        </bibdata>
      XML
      item = Relaton::Iso::Item.from_xml(xml)
      tc_id = item.docidentifier.find { |d| d.type == "iso-tc" }
      expect(tc_id.to_s).to eq "ISO/TC 184/SC 4 N1110"
    end
  end

  context "#exclude_year" do
    let(:type) { "ISO" }

    it "removes year from a simple identifier" do
      docid = described_class.new content: "ISO 19115:2014", type: type
      result = docid.exclude_year
      expect(result.to_s).not_to include("2014")
      expect(result.to_s).to eq("ISO 19115")
    end

    it "removes year from identifier and its base" do
      docid = described_class.new content: "ISO 19115-1:2014/Amd 1:2018", type: type
      result = docid.exclude_year
      expect(result.to_s).to eq("ISO 19115-1/Amd 1")
    end
  end
end
