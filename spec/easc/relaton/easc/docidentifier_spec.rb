require "relaton/easc"

RSpec.describe Relaton::Easc::Docidentifier do
  subject(:docid) { described_class.new(content: "ПМГ 03-2025", type: "EASC") }

  it "parses its content into a pubid" do
    expect(docid.pubid).to be_a Pubid::Easc::Identifier
    expect(docid.pubid.number).to eq "03"
    expect(docid.pubid.year).to eq "2025"
  end

  it "leaves the pubid nil for content it cannot parse" do
    expect(described_class.new(content: "not an identifier").pubid).to be_nil
  end

  it "#remove_date! strips the year, EASC's edition discriminator" do
    docid.remove_date!
    expect(docid.content).to eq "ПМГ 03"
  end

  it "#remove_part! does not raise, though EASC models no part" do
    expect { docid.remove_part! }.not_to raise_error
    expect(docid.content).to eq "ПМГ 03-2025"
  end

  it "#to_all_parts! strips the year" do
    docid.to_all_parts!
    expect(docid.content).to eq "ПМГ 03"
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

  # The point of the class: Bib::Docidentifier's versions raise
  # NotImplementedError, which ItemData broadcasts to every docidentifier.
  describe "through Bib::ItemData" do
    let(:item) do
      Relaton::Easc::Item.from_yaml File.read(
        File.join(__dir__, "..", "..", "fixtures", "data", "pmg-03-2025.yaml"),
      )
    end

    it "#to_all_parts no longer raises" do
      expect(item.to_all_parts.docidentifier.first.content).to eq "ПМГ 03"
    end

    it "#to_most_recent_reference no longer raises" do
      expect(item.to_most_recent_reference.docidentifier.first.content).to eq "ПМГ 03"
    end
  end
end
