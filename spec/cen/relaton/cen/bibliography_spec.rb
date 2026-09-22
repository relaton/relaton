# frozen_string_literal: true

# Hit selection, unit-tested. These examples make no HTTP request: they drive
# pubid's subset match `query === hit` directly, which is the whole of
# `search_filter`'s decision. The cassettes cover the flow around it.
RSpec.describe Relaton::Cen::Bibliography do
  def parse(ref)
    described_class.parse ref
  end

  def selects?(query, hit)
    parse(query) === parse(hit)
  end

  describe ".search_filter" do
    it "keeps the hits that the query selects, and drops an unparseable one" do
      codes = ["EN 1325-1:1996", "EN 1325:2014", "prEN 1325", "EN 13250:2000", nil]
      hits = codes.map { |c| instance_double(Relaton::Cen::Hit, pubid: c && parse(c)) }
      collection = Relaton::Core::HitCollection.allocate
      collection.instance_variable_set(:@array, hits)
      allow(described_class).to receive(:search).with("EN 1325").and_return(collection)

      selected = described_class.send(:search_filter, "EN 1325", parse("EN 1325"))
      expect(selected.map { |h| h.pubid.to_s }).to eq ["EN 1325-1:1996", "EN 1325:2014"]
    end
  end

  describe ".parse" do
    it "raises on a reference that is not an identifier" do
      expect { parse "CEN NOT FOUND" }.to raise_error Pubid::Errors::ParseError
    end

    it "raises on a portal draft revision, which is not a caller reference" do
      expect { parse "prEN 13306 rev" }.to raise_error Pubid::Errors::ParseError
    end
  end

  describe "selection" do
    it "matches any part and any year for a bare reference" do
      expect(selects?("EN 1325", "EN 1325-1:1996")).to be true
      expect(selects?("EN 1325", "EN 1325:2014")).to be true
    end

    it "does not match a different number that shares a prefix" do
      expect(selects?("EN 1325", "EN 13250:2000")).to be false
    end

    it "matches any year for a part-and-number reference" do
      expect(selects?("CEN ISO/TS 21003-7", "CEN ISO/TS 21003-7:2019")).to be true
    end

    it "narrows on the year when the reference names one" do
      expect(selects?("EN 13306:2017", "EN 13306:2017")).to be true
      expect(selects?("EN 13306:2017", "EN 13306:2010")).to be false
    end

    # A base reference must never answer with its own amendment's record.
    # pubid's `===` requires identical classes, and it documents that a
    # reference never falls back to the base document of a wrapper. These
    # examples fail loudly if pubid ever relaxes it.
    it "never selects a supplement for a base reference" do
      expect(selects?("CEN ISO/TS 21003-7", "CEN ISO/TS 21003-7:2008/A1:2010"))
        .to be false
      expect(selects?("EN 13250:2000", "EN 13250:2000/A1:2005")).to be false
      expect(selects?("EN 285:2015", "EN 285:2015+A1:2021")).to be false
      expect(selects?("HD 1215-2:1988", "HD 1215-2:1988/AC1:1989")).to be false
    end

    it "never selects a base document for a supplement reference" do
      expect(selects?("EN 285:2015+A1", "EN 285:2015")).to be false
    end

    it "matches a supplement's year only when the reference omits it" do
      expect(selects?("EN 13250:2000/A1", "EN 13250:2000/A1:2005")).to be true
      expect(selects?("EN 13250:2000/A1:2005", "EN 13250:2000/A1:2005")).to be true
      expect(selects?("EN 13250:2000/A1:2006", "EN 13250:2000/A1:2005")).to be false
    end

    it "keeps two supplements of one document apart" do
      expect(selects?("EN 13250:2000/A1", "EN 13250:2000/A2:2005")).to be false
      expect(selects?("EN 13250:2000/A1", "EN 13250:2014+A1:2015")).to be false
    end

    it "keeps the same supplement of two documents apart" do
      expect(selects?("EN 13250:2000/A1", "EN 13251:2000/A1:2005")).to be false
    end

    # pubid declares the CEN `type`, `stage` and `typed_stage` strict, so a
    # reference without a stage means the published document, not "any stage".
    it "does not select a draft for a published reference" do
      expect(selects?("EN 1325", "prEN 1325")).to be false
      expect(selects?("EN 1325", "prEN 1325-1:2023")).to be false
    end

    it "does not cross the document type" do
      expect(selects?("EN 1325", "CEN/TS 1325")).to be false
      expect(selects?("CEN/TS 1325", "EN 1325")).to be false
    end

    it "does not cross the adopted document type" do
      expect(selects?("CEN ISO/TS 21003-7", "EN ISO 21003-7:2019")).to be false
    end
  end
end
