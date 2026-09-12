# frozen_string_literal: true

# Hit selection, unit-tested. These examples make no HTTP request: they drive
# the ignore-list rule and pubid's `matches?` directly, which is the whole of
# `search_filter`'s decision. The cassettes cover the flow around it.
RSpec.describe Relaton::Cen::Bibliography do
  def parse(ref)
    described_class.parse ref
  end

  def selects?(query, hit)
    q = parse query
    q.matches? parse(hit), ignore: described_class.send(:ignored_components, q)
  end

  describe ".parse" do
    it "raises on a reference that is not an identifier" do
      expect { parse "CEN NOT FOUND" }.to raise_error Pubid::Errors::ParseError
    end

    it "raises on a portal draft revision, which is not a caller reference" do
      expect { parse "prEN 13306 rev" }.to raise_error Pubid::Errors::ParseError
    end
  end

  describe "the ignore list" do
    {
      "EN 13306" => %i[part subpart year],
      "EN 13306:2017" => %i[part subpart],
      "EN 1325-1:1996" => [],
      "CEN ISO/TS 21003-7" => %i[year],
      "CEN ISO/TS 21003-7:2019" => [],
      # A supplement WITH a year narrows on that year; without one it does not.
      "EN 13250:2000/A1:2005" => %i[part subpart],
      "EN 13250:2000/A1" => %i[part subpart supplement_year],
      "EN 285:2015+A1:2021" => %i[part subpart],
      "EN 285:2015+A1" => %i[part subpart supplement_year],
    }.each do |ref, expected|
      it "ignores #{expected.inspect} for #{ref}" do
        expect(described_class.send(:ignored_components, parse(ref)))
          .to eq expected
      end
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

    # The rule the `supplement?` guard in `ignored_components` states: a base
    # reference must never answer with its own amendment's record. pubid's `==`
    # is class-strict, so it enforces this today even without the guard; the
    # guard keeps the rule explicit rather than inherited by luck, and these
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
  end
end
