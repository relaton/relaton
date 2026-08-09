require "relaton/itu/recommendation_parser"

# RecommendationFields is the shared extractor mixed into RecommendationParser
# (live path) and reused by DataParserT (harvester). Exercise it through its
# canonical includer.
RSpec.describe Relaton::Itu::RecommendationFields do
  let(:agent) { instance_double Mechanize }
  subject(:fields) { Relaton::Itu::RecommendationParser.new(agent, 5194, false) }

  def stub_detail(hash)
    allow(agent).to receive(:get).with(a_string_including("getRecHdrDetail"))
      .and_return(double("resp", body: hash.to_json))
  end

  describe "#iso_docid" do
    it "extracts an ISO/IEC equivalent from iso_number" do
      stub_detail("iso_number" => "ISO/IEC 17788:2014 (Common)")
      id = fields.iso_docid
      expect(id).to be_instance_of Relaton::Itu::Docidentifier
      expect(id.type).to eq "ISO"
      expect(id.content).to eq "ISO/IEC 17788"
      expect(id.primary).to be true
    end

    it "extracts a bare ISO number" do
      stub_detail("iso_number" => "ISO 128-1")
      expect(fields.iso_docid.content).to eq "ISO 128-1"
    end

    it "keeps a deliverable (TR/TS/Guide) form" do
      stub_detail("iso_number" => "ISO/IEC TR 29110 (Overview)")
      expect(fields.iso_docid.content).to eq "ISO/IEC TR 29110"
    end

    it "returns nil when there is no iso_number" do
      stub_detail({})
      expect(fields.iso_docid).to be_nil
    end
  end

  describe "#fetch_abstract" do
    it "maps summary to an Abstract" do
      stub_detail("summary" => "An overview.")
      expect(fields.fetch_abstract.first.content.to_s).to eq "An overview."
    end

    it "is empty without a summary" do
      stub_detail({})
      expect(fields.fetch_abstract).to eq []
    end
  end

  describe "#publisher" do
    it "builds the ITU publisher contributor" do
      c = fields.publisher("ITU")
      expect(c.organization.abbreviation.content).to eq "ITU"
      expect(c.role.first.type).to eq "publisher"
    end

    it "returns nil for a non-ITU abbreviation" do
      expect(fields.publisher(nil)).to be_nil
    end
  end

  describe "#group_subdivision" do
    it "maps an Advisory Group to tsag" do
      expect(fields.group_subdivision("Telecommunication Standardization Advisory Group").first.subtype).to eq "tsag"
    end

    it "maps a Study Group" do
      expect(fields.group_subdivision("Study Group 13").first.subtype).to eq "study-group"
    end

    it "falls back to work-group" do
      expect(fields.group_subdivision("Focus Group on AI").first.subtype).to eq "work-group"
    end

    it "is empty without a name" do
      expect(fields.group_subdivision(nil)).to eq []
    end
  end

  describe "#editorial_group" do
    it "builds a study-group contributor from the rec.aspx workgroup" do
      page = double("page")
      allow(page).to receive(:at).and_return(double("wg", text: "Study Group 17"))
      allow(agent).to receive(:get).with(a_string_including("rec.aspx")).and_return(page)

      c = fields.editorial_group("T")
      expect(c.organization.abbreviation.content).to eq "ITU-T"
      expect(c.organization.subdivision.first.subtype).to eq "study-group"
      expect(c.role.first.description.first.content).to eq "committee"
    end

    it "returns nil without a bureau" do
      expect(fields.editorial_group(nil)).to be_nil
    end
  end
end
