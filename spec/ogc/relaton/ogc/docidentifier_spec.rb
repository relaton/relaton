require "relaton/ogc"

RSpec.describe Relaton::Ogc::Docidentifier do
  subject(:docid) { described_class.new(content: "12-128r19", type: "OGC") }

  it "parses its content into a pubid" do
    expect(docid.pubid).to be_a Pubid::Ogc::Identifier
    expect(docid.pubid.year).to eq "12"
    expect(docid.pubid.number).to eq "128"
    expect(docid.pubid.revision).to eq "r19"
  end

  it "leaves the pubid nil for content it cannot parse" do
    expect(described_class.new(content: "not an identifier").pubid).to be_nil
  end

  it "keeps content a plain string" do
    expect(docid.content).to be_a String
  end

  describe "#remove_date!" do
    it "clears the revision, OGC's version discriminator" do
      docid.remove_date!
      expect(docid.content).to eq "12-128"
    end

    it "keeps the year, which is half the document number" do
      docid.remove_date!
      expect(docid.pubid.year).to eq "12"
    end
  end

  describe "#remove_part!" do
    it "does not raise, though OGC models no part" do
      expect { docid.remove_part! }.not_to raise_error
      expect(docid.content).to eq "12-128r19"
    end
  end

  describe "#to_all_parts!" do
    it "strips the revision and flags the identifier" do
      docid.to_all_parts!
      expect(docid.content).to eq "12-128"
    end
  end

  context "when the pubid is nil" do
    subject(:docid) { described_class.new(content: "not an identifier") }

    # The point of the class: Bib::Docidentifier's versions raise
    # NotImplementedError, which ItemData broadcasts to every docidentifier.
    it "no-ops instead of raising" do
      expect { docid.remove_part! }.not_to raise_error
      expect { docid.remove_date! }.not_to raise_error
      expect { docid.to_all_parts! }.not_to raise_error
      expect(docid.content).to eq "not an identifier"
    end
  end

  describe "through Bib::ItemData" do
    let(:item) do
      Relaton::Ogc::Item.from_yaml File.read(File.join(__dir__, "..", "..", "fixtures", "item.yaml"))
    end

    it "#to_all_parts no longer raises" do
      expect(item.to_all_parts.docidentifier.first.content).to eq "19-025"
    end

    it "#to_most_recent_reference no longer raises" do
      expect(item.to_most_recent_reference.docidentifier.first.content).to eq "19-025"
    end
  end
end
