require "relaton/itu/scraper"

RSpec.describe Relaton::Itu::Scraper do
  describe "#docid" do
    def scraper_for(hit_hash, parser = nil)
      hit = double("Hit", hit: hit_hash)
      described_class.new(hit).tap do |s|
        allow(s).to receive(:parser).and_return(parser) if parser
      end
    end

    it "appends the equivalent ISO identifier from the recommendation header" do
      parser = double("RecommendationParser",
                      iso_docid: Relaton::Itu::Docidentifier.new(
                        type: "ISO", content: "ISO/IEC 17788", primary: true
                      ))
      scraper = scraper_for({ code: "ITU-T Y.3500 (08/2014)",
                              url: "http://handle.itu.int/11.1002/1000/12210-en",
                              type: "recommendation" }, parser)

      docids = scraper.send(:docid)
      expect(docids.map(&:content)).to eq ["ITU-T Y.3500 (08/2014)", "ISO/IEC 17788"]
      expect(docids.map(&:type)).to eq %w[ITU ISO]
    end

    it "falls back to the header's rec_name when the hit carries no code" do
      parser = double("RecommendationParser", doc: { "rec_name" => "Y.3500 (08/2014)" }, iso_docid: nil)
      scraper = scraper_for({ url: "http://handle.itu.int/11.1002/1000/12210-en" }, parser)

      expect(scraper.send(:docid).map(&:content)).to eq ["ITU-T Y.3500 (08/2014)"]
    end

    it "adds no ISO identifier for a publication (no idrec)" do
      scraper = scraper_for(code: "ITU-R RR (2020)",
                            url: "https://www.itu.int/pub/R-REG-RR-2020",
                            type: "publication")

      expect(scraper.send(:docid).map(&:content)).to eq ["ITU-R RR (2020)"]
    end

    # The code is data from ITU, not the caller's reference: a spelling pubid
    # cannot identify is kept as ITU wrote it rather than failing the record.
    it "keeps a code pubid cannot parse as it is" do
      parser = double("RecommendationParser", doc: { "rec_name" => "G 231 (10/1976)" }, iso_docid: nil)
      scraper = scraper_for({ url: "http://handle.itu.int/11.1002/1000/1-en" }, parser)

      docid = scraper.send(:docid).first
      expect(docid.content).to eq "ITU-T G 231 (10/1976)"
      expect(docid.type).to eq "ITU"
    end
  end

  # The publisher, the bureau and the copyright owner come from the pubid
  # parse of the hit code, not from its spelling: an Operational Bulletin
  # prints no sector (pubid#696), but TSB produces it.
  describe "contributors" do
    def scraper_for(code)
      parser = double("Parser", fetch_workgroup: nil, doc_date: "2016-03-15")
      described_class.new(double("Hit", hit: { code: code })).tap do |s|
        allow(s).to receive(:parser).and_return(parser)
      end
    end

    def publisher(scraper)
      scraper.send(:fetch_publisher_contributors).map(&:organization).first
    end

    def author_abbreviation(scraper)
      contrib = scraper.send(:fetch_editorial_contributor)
      contrib && contrib.organization.abbreviation.content
    end

    it "makes ITU the publisher and ITU-T the author of an Operational Bulletin" do
      scraper = scraper_for "ITU OB No. 1096 (2016)"

      org = publisher(scraper)
      expect(org.name.first.content).to eq "International Telecommunication Union"
      expect(org.abbreviation.content).to eq "ITU"
      expect(org.uri.first.content).to eq "www.itu.int"
      expect(author_abbreviation(scraper)).to eq "ITU-T"

      owner = scraper.send(:fetch_copyright).first.owner.first.organization
      expect(owner.name.first.content).to eq "International Telecommunication Union"
      expect(owner.abbreviation.content).to eq "ITU"
    end

    it "takes the bureau from the sector" do
      expect(author_abbreviation(scraper_for("ITU-R RR (2020)"))).to eq "ITU-R"
      expect(author_abbreviation(scraper_for("ITU-T Y.3500 (08/2014)"))).to eq "ITU-T"
      expect(author_abbreviation(scraper_for("ITU-T Y.3500 | ISO/IEC 17788"))).to eq "ITU-T"
    end

    it "takes the bureau of the wrapped document for an annex" do
      expect(author_abbreviation(scraper_for("ITU-T H.264 Annex A"))).to eq "ITU-T"
    end

    it "keeps ITU as publisher but adds no author for a code pubid cannot parse" do
      scraper = scraper_for "ITU-T G 231 (10/1976)"

      expect(publisher(scraper).abbreviation.content).to eq "ITU"
      expect(author_abbreviation(scraper)).to be_nil
    end

    it "adds no publisher or author for a hit with no code" do
      scraper = scraper_for nil

      expect(scraper.send(:fetch_publisher_contributors)).to eq []
      expect(author_abbreviation(scraper)).to be_nil
      owner = scraper.send(:fetch_copyright).first.owner.first.organization
      expect(owner.abbreviation.content).to eq "ITU"
    end
  end

  context "when server is unavailable" do
    it "raises RequestError" do
      agent = double "Mechanize agent"
      expect(agent).to receive(:get)
        .and_raise Mechanize::ResponseCodeError.new(Mechanize::Page.new)
      hit_collection = double("Hit collection", agent: agent)
      hit = double(
        "Hit",
        hit_collection: hit_collection,
        hit: { url: "https://www.itu.int/rec/T-REC-G.191/12345-rec", code: "ITU-T G.191", type: "recommendation" },
      )
      expect do
        Relaton::Itu::Scraper.parse_page(hit)
      end.to raise_error(Relaton::RequestError, /Could not access/)
    end
  end
end
