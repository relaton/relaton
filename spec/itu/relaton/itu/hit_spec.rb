describe Relaton::Itu::Hit do
  let(:scraper) { double("Scraper") }
  let(:hit_hash) { { code: "ITU-T A.1", title: "Test", url: "https://example.com" } }
  let(:hit_collection) { nil }

  subject { described_class.new(hit_hash, hit_collection) }

  before { stub_const("Relaton::Itu::Scraper", scraper) }

  describe "#item" do
    it "delegates to Scraper.parse_page" do
      parsed = double("item")
      expect(scraper).to receive(:parse_page)
        .with(subject, imp: false).and_return(parsed)
      expect(subject.item).to eq parsed
    end

    it "memoizes the result" do
      parsed = double("item")
      expect(scraper).to receive(:parse_page).once.and_return(parsed)
      2.times { subject.item }
    end

    context "with ref containing .Imp" do
      let(:hit_hash) { { code: "ITU-T A.1", title: "Test", url: "https://example.com", ref: "ITU-T A.1.Imp1" } }

      it "passes imp: true" do
        parsed = double("item")
        expect(scraper).to receive(:parse_page)
          .with(subject, imp: true).and_return(parsed)
        expect(subject.item).to eq parsed
      end
    end
  end

  describe "#item=" do
    it "allows setting item directly" do
      item = double("item")
      subject.item = item
      expect(subject.item).to eq item
    end
  end
end
