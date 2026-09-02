require "relaton/gost"

RSpec.describe Relaton::Gost::Docidentifier do
  subject(:docid) { described_class.new(content: "GOST R 34.12-2015", type: "GOST") }

  it "parses its content into a pubid" do
    expect(docid.pubid).to be_a Pubid::Gost::Identifier
    expect(docid.pubid.number).to eq "34.12"
    expect(docid.pubid.year).to eq "2015"
  end

  it "#remove_date! strips the year, GOST's edition discriminator" do
    docid.remove_date!
    expect(docid.content).to eq "GOST R 34.12"
  end

  it "#remove_part! does not raise, though GOST models no part" do
    expect { docid.remove_part! }.not_to raise_error
    expect(docid.content).to eq "GOST R 34.12-2015"
  end

  it "#to_all_parts! strips the year" do
    docid.to_all_parts!
    expect(docid.content).to eq "GOST R 34.12"
  end

  # refresh_content! writes through store_content rather than content=, so an
  # in-place mutation is not discarded by a re-parse.
  it "keeps the all_parts flag set by #to_all_parts!" do
    docid.to_all_parts!
    expect(docid.pubid.all_parts).to be true
  end

  context "when the pubid is nil" do
    subject(:docid) { described_class.new(content: "not an identifier") }

    it "no-ops instead of raising" do
      expect { docid.remove_part! }.not_to raise_error
      expect { docid.remove_date! }.not_to raise_error
      expect { docid.to_all_parts! }.not_to raise_error
      expect(docid.content).to eq "not an identifier"
    end
  end

  describe "through Bib::ItemData" do
    let(:item) do
      Relaton::Gost::Item.from_yaml File.read(
        File.join(__dir__, "..", "..", "fixtures", "data", "gost-r-34.12-2015.yaml"),
      )
    end

    it "#to_all_parts no longer raises" do
      expect(item.to_all_parts.docidentifier.first.content).to eq "GOST R 34.12"
    end

    it "#to_most_recent_reference still works" do
      expect(item.to_most_recent_reference.docidentifier.first.content).to eq "GOST R 34.12"
    end
  end
end
