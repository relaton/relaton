require "relaton/ecma"

RSpec.describe Relaton::Ecma::Docidentifier do
  subject(:docid) { described_class.new(content: "ECMA-269", type: "ECMA") }

  it "parses its content into a pubid" do
    expect(docid.pubid).to be_a Pubid::Ecma::Identifier
    expect(docid.pubid.number).to eq "269"
  end

  it "keeps content a plain string" do
    expect(docid.content).to be_a String
    expect(docid.content).to eq "ECMA-269"
  end

  it "leaves the pubid nil for content it cannot parse" do
    expect(described_class.new(content: "ECMA TR-27").pubid).to be_nil
  end

  it "distinguishes a technical report from a standard" do
    expect(described_class.new(content: "ECMA TR/101").pubid)
      .to be_a Pubid::Ecma::Identifiers::TechnicalReport
    expect(docid.pubid).to be_a Pubid::Ecma::Identifiers::Standard
  end

  # The trap this class exists for: the stored content is the BARE document
  # form, while pubid renders the edition and the volume by DEFAULT. Every
  # mutator re-renders through `refresh_content!`, so each one has to keep the
  # content bare — hence the check here rather than under one method's describe.
  describe "re-rendering after any mutation" do
    it "never promotes a bare content to the index form" do
      docid.pubid.edition = "3"
      docid.pubid.volume = "2"

      expect { docid.remove_part! }.not_to change(docid, :content).from("ECMA-269")
      expect { docid.remove_date! }.not_to change(docid, :content).from("ECMA-269")
      expect { docid.to_all_parts! }.not_to change(docid, :content).from("ECMA-269")
    end
  end

  describe "#remove_date!" do
    it "clears the edition, ECMA's version discriminator" do
      docid = described_class.new(content: "ECMA-269 ed3")
      docid.remove_date!
      expect(docid.pubid.edition).to be_nil
      expect(docid.content).to eq "ECMA-269"
    end
  end

  describe "#remove_part!" do
    it "clears the part" do
      docid = described_class.new(content: "ECMA-418-1")
      docid.remove_part!
      expect(docid.content).to eq "ECMA-418"
    end

    it "leaves the edition alone" do
      docid = described_class.new(content: "ECMA-418-1 ed2")
      docid.remove_part!
      expect(docid.pubid.part).to be_nil
      expect(docid.pubid.edition).to eq "2"
    end
  end

  describe "#to_all_parts!" do
    it "strips the part and the edition" do
      docid = described_class.new(content: "ECMA-418-1 ed2")
      docid.to_all_parts!
      expect(docid.pubid.part).to be_nil
      expect(docid.pubid.edition).to be_nil
      expect(docid.content).to eq "ECMA-418"
    end
  end

  context "when the pubid is nil" do
    subject(:docid) { described_class.new(content: "not an identifier") }

    # Bib::ItemData broadcasts all three to every docidentifier.
    it "no-ops instead of raising" do
      expect { docid.remove_part! }.not_to raise_error
      expect { docid.remove_date! }.not_to raise_error
      expect { docid.to_all_parts! }.not_to raise_error
      expect(docid.content).to eq "not an identifier"
    end
  end

  describe "through Bib::ItemData" do
    let(:item) do
      Relaton::Ecma::ItemData.new(
        docidentifier: [described_class.new(content: "ECMA-418-1", type: "ECMA")],
      )
    end

    it "#to_all_parts no longer raises" do
      expect(item.to_all_parts.docidentifier.first.content).to eq "ECMA-418"
    end

    it "#to_most_recent_reference no longer raises" do
      expect(item.to_most_recent_reference.docidentifier.first.content).to eq "ECMA-418-1"
    end
  end

  describe "the item's parsed docidentifier" do
    it "is this class, not the base one" do
      item = Relaton::Ecma::Item.from_yaml <<~YAML
        docidentifier:
          - content: ECMA-269
            type: ECMA
            primary: true
      YAML
      expect(item.docidentifier.first).to be_a described_class
      expect(item.docidentifier.first.pubid.number).to eq "269"
    end
  end
end
