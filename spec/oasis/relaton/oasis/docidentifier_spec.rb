# frozen_string_literal: true

RSpec.describe Relaton::Oasis::Docidentifier do
  subject(:docid) do
    described_class.new(type: "OASIS", primary: true,
                        content: "OASIS OSLC-CoreShapes-3.0-PS01-Pt8")
  end

  describe "#pubid" do
    it "parses the content into a pubid identifier" do
      expect(docid.pubid).to be_a Pubid::Oasis::Identifiers::Standard
      expect(docid.pubid.to_s).to eq "OASIS OSLC-CoreShapes-3.0-PS01-Pt8"
    end

    it "decomposes the slug" do
      expect(docid.pubid.number).to eq "OSLC-CoreShapes"
      expect(docid.pubid.version).to eq "3.0"
      expect(docid.pubid.stage).to eq "PS01"
      expect(docid.pubid.part).to eq "Pt8"
    end

    it "keeps the content a plain string" do
      expect(docid.content).to be_a String
      expect(docid.content).to eq "OASIS OSLC-CoreShapes-3.0-PS01-Pt8"
    end

    it "accepts an id without the publisher token" do
      id = described_class.new(content: "amqp-core")
      expect(id.pubid).to be_nil
      expect(id.content).to eq "amqp-core"
    end

    it "is nil when pubid cannot parse the content" do
      id = described_class.new(content: "")
      expect(id.pubid).to be_nil
    end
  end

  # The three mutators are no-ops for OASIS. `Pubid::Oasis::Renderer` echoes
  # `original` verbatim, so clearing a component cannot change the printed id.
  describe "the inherited mutators" do
    it "leaves the content unchanged" do
      docid.remove_part!
      docid.remove_date!
      docid.to_all_parts!
      expect(docid.content).to eq "OASIS OSLC-CoreShapes-3.0-PS01-Pt8"
    end

    it "does not raise when the pubid is nil" do
      id = described_class.new(content: "")
      expect { id.remove_part! }.not_to raise_error
      expect { id.remove_date! }.not_to raise_error
      expect { id.to_all_parts! }.not_to raise_error
    end
  end

  describe "through Bib::ItemData" do
    subject(:item) { Relaton::Oasis::ItemData.new docidentifier: [docid] }

    it "does not raise on #to_all_parts" do
      expect { item.to_all_parts }.not_to raise_error
    end

    it "does not raise on #to_most_recent_reference" do
      expect { item.to_most_recent_reference }.not_to raise_error
    end
  end
end
