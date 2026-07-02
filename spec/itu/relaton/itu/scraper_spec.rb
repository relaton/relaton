require "relaton/itu/scraper"

RSpec.describe Relaton::Itu::Scraper do
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
