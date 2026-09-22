# frozen_string_literal: true

RSpec.describe Relaton::Gb::Bibliography do
  def hits(*docrefs)
    Relaton::Gb::HitCollection.new(
      docrefs.map { |ref| Relaton::Gb::Hit.new(pid: ref, docref: ref, scraper: nil) },
    )
  end

  describe ".get" do
    it "raises on a reference that is not a GB identifier" do
      expect { described_class.get "foo" }.to raise_error Pubid::Errors::ParseError
    end

    it "searches with the year taken from the code" do
      expect(described_class).to receive(:search).with("GB/T 20223-2006").and_return hits
      described_class.get "GB/T 20223-2006"
    end

    it "searches with the year given as an argument" do
      expect(described_class).to receive(:search).with("GB/T 20223-2006").and_return hits
      described_class.get "GB/T 20223", 2006
    end

    it "searches for part 1 of an all-parts reference" do
      expect(described_class).to receive(:search).with("GB/T 5606.1-2004").and_return hits
      described_class.get "GB/T 5606", "2004", all_parts: true
    end
  end

  describe ".search_filter" do
    def filter(code, *docrefs)
      allow(described_class).to receive(:search).and_return hits(*docrefs)
      described_class.send(:search_filter, Pubid::Gb::Identifier.parse(code)).map(&:docref)
    end

    it "keeps every year of an undated reference" do
      expect(filter("GB/T 1.1", "GB/T 1.1-2020", "GB/T 1.1-2009"))
        .to eq ["GB/T 1.1-2020", "GB/T 1.1-2009"]
    end

    it "rejects a document whose number only starts with the queried one" do
      expect(filter("GB/T 1.1", "GB/T 1.1-2020", "GB/T 1.10-2008")).to eq ["GB/T 1.1-2020"]
    end

    it "rejects another year of a dated reference" do
      expect(filter("GB/T 1.1-2009", "GB/T 1.1-2020", "GB/T 1.1-2009")).to eq ["GB/T 1.1-2009"]
    end

    it "rejects a part of a part-less reference" do
      expect(filter("GB/T 20223-2006", "GB/T 20223.1-2006", "GB/T 20223-2006"))
        .to eq ["GB/T 20223-2006"]
    end

    it "rejects a hit whose docref is not a GB identifier" do
      expect(filter("GB/T 1.1", "not an id", "GB/T 1.1-2020")).to eq ["GB/T 1.1-2020"]
    end
  end
end
