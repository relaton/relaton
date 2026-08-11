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
