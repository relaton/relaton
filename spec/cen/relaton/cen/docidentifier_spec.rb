# frozen_string_literal: true

RSpec.describe Relaton::Cen::Docidentifier do
  def docid(content)
    described_class.new(type: "CEN", content: content, primary: true)
  end

  it "parses its content into a pubid" do
    expect(docid("EN 13306:2017").pubid)
      .to be_a Pubid::CenCenelec::Identifiers::EuropeanNorm
  end

  it "keeps a non-CEN value verbatim, with no pubid" do
    id = docid("ISBN 978-92-67-10790-9")

    expect(id.pubid).to be_nil
    expect(id.content).to eq "ISBN 978-92-67-10790-9"
  end

  it "keeps an unparseable CEN-looking value verbatim, with no pubid" do
    id = docid("prEN 13306 rev")

    expect(id.pubid).to be_nil
    expect(id.content).to eq "prEN 13306 rev"
  end

  # `remove_date!` drops the LAST year only. On a supplement the identifier
  # names the supplement, so its own year is the last one; the earlier year
  # belongs to the base document it supplements, and dropping that would strip
  # the base document's identity rather than a date.
  describe "#remove_date!" do
    {
      "EN 13306:2017" => "EN 13306",
      "EN 1325-1:1996" => "EN 1325-1",
      "CWA 14050-21:2000" => "CWA 14050-21",
      "HD 1215-2:1988" => "HD 1215-2",
      "CR 12101-5:2000" => "CR 12101-5",
      "ENV 1613:1995" => "ENV 1613",
      "CEN ISO/TS 21003-7:2019" => "CEN ISO/TS 21003-7",
      "EN 13250:2000/A1:2005" => "EN 13250:2000/A1",
      "EN 285:2015+A1:2021" => "EN 285:2015+A1",
      "CEN ISO/TS 21003-7:2008/A1:2010" => "CEN ISO/TS 21003-7:2008/A1",
      # The old `/:\d{4}$/` regex did not match this one, because the string
      # ends `-11`, so it stripped nothing. `exclude(:supplement_year)` resets
      # the supplement's year and month together.
      "EN 61375-2-3:2015/AC:2016-11" => "EN 61375-2-3:2015/AC",
      # The only year here belongs to the base document, so it is also the last
      # one. The old regex left this unchanged, which removed no date at all.
      "EN 285:2015+A1" => "EN 285+A1",
    }.each do |input, expected|
      it "turns #{input} into #{expected}" do
        id = docid(input)
        id.remove_date!

        expect(id.content).to eq expected
      end
    end

    it "leaves an undated reference alone" do
      id = docid("EN 13306")
      id.remove_date!

      expect(id.content).to eq "EN 13306"
    end

    it "no-ops when the content has no pubid" do
      id = docid("prEN 13306 rev")

      expect { id.remove_date! }.not_to raise_error
      expect(id.content).to eq "prEN 13306 rev"
    end
  end

  describe "#remove_part!" do
    {
      "EN 1325-1:1996" => "EN 1325:1996",
      "CWA 14050-21:2000" => "CWA 14050:2000",
      "HD 1215-2:1988" => "HD 1215:1988",
      "CR 12101-5:2000" => "CR 12101:2000",
      "CEN ISO/TS 21003-7:2019" => "CEN ISO/TS 21003:2019",
      "EN 61375-2-3:2015/AC:2016-11" => "EN 61375:2015/AC:2016-11",
      "EN 13306:2017" => "EN 13306:2017",
      "ENV 1613:1995" => "ENV 1613:1995",
    }.each do |input, expected|
      it "turns #{input} into #{expected}" do
        id = docid(input)
        id.remove_part!

        expect(id.content).to eq expected
      end
    end

    it "no-ops when the content has no pubid" do
      id = docid("prEN 13306 rev")

      expect { id.remove_part! }.not_to raise_error
      expect(id.content).to eq "prEN 13306 rev"
    end
  end

  describe "#to_all_parts!" do
    {
      "EN 1325-1:1996" => "EN 1325",
      "CWA 14050-21:2000" => "CWA 14050",
      "CEN ISO/TS 21003-7:2019" => "CEN ISO/TS 21003",
      "EN 13250:2000/A1:2005" => "EN 13250:2000/A1",
      "EN 61375-2-3:2015/AC:2016-11" => "EN 61375:2015/AC",
    }.each do |input, expected|
      it "turns #{input} into #{expected}" do
        id = docid(input)
        id.to_all_parts!

        expect(id.content).to eq expected
      end
    end

    it "no-ops when the content has no pubid" do
      id = docid("prEN 13306 rev")

      expect { id.to_all_parts! }.not_to raise_error
      expect(id.content).to eq "prEN 13306 rev"
    end
  end

  # A write must not re-parse: the re-rendered string goes back through the
  # aliased inherited setter, so an in-place flag such as `all_parts` survives.
  it "re-renders through the inherited setter, keeping the mutated pubid" do
    id = docid("EN 1325-1:1996")
    id.to_all_parts!

    expect(id.pubid.to_s).to eq "EN 1325"
    expect(id.content).to eq "EN 1325"
  end
end
