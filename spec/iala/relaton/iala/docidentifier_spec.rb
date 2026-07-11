require "relaton/iala"

RSpec.describe Relaton::Iala::Docidentifier do
  describe "#initialize / #content=" do
    it "parses content into a Pubid::Iala identifier" do
      d = described_class.new(content: "IALA S1070 Ed 2.0", type: "IALA", primary: true)
      expect(d.pubid).to be_a Pubid::Iala::Identifier
      expect(d.pubid.number).to eq "1070"
      expect(d.pubid.edition).to eq "2.0"
      expect(d.content).to eq "IALA S1070 Ed 2.0"
    end

    it "accepts a parsed Pubid object via the :pubid keyword" do
      require "pubid"
      require "pubid/iala"
      pubid = Pubid::Iala.parse("IALA S1070 Ed 2.0")
      d = described_class.new(pubid: pubid, type: "IALA", primary: true)
      expect(d.pubid).to equal pubid
      expect(d.content).to eq "IALA S1070 Ed 2.0"
    end

    it "leaves @pubid nil on unparseable content (soft rescue, no raise)" do
      expect { @d = described_class.new(content: "not a real ref", type: "IALA") }
        .not_to raise_error
      expect(@d.pubid).to be_nil
      expect(@d.content).to eq "not a real ref"
    end

    it "leaves @pubid nil when content is empty" do
      d = described_class.new(type: "IALA")
      expect(d.pubid).to be_nil
    end
  end

  describe "#remove_date!" do
    # IALA has no date component; `edition` is its version discriminator, so
    # remove_date! strips the edition ("most recent" reference).
    it "clears the edition and re-renders the content" do
      d = described_class.new(content: "IALA S1070 Ed 2.0", type: "IALA", primary: true)
      d.remove_date!
      expect(d.pubid.edition).to be_nil
      expect(d.content).to eq "IALA S1070"
    end

    it "is a safe no-op when pubid is nil" do
      d = described_class.new(type: "IALA")
      expect { d.remove_date! }.not_to raise_error
      expect(d.pubid).to be_nil
    end
  end

  describe "#remove_part!" do
    # Documented no-op for the current IALA model: any subpart is folded inline
    # into `number` (e.g. "0103-1"), so the rendered content is unchanged.
    it "does not raise and leaves the rendered content intact" do
      d = described_class.new(content: "IALA S1070 Ed 2.0", type: "IALA", primary: true)
      expect { d.remove_part! }.not_to raise_error
      expect(d.content).to eq "IALA S1070 Ed 2.0"
    end

    it "is a safe no-op when pubid is nil" do
      d = described_class.new(type: "IALA")
      expect { d.remove_part! }.not_to raise_error
      expect(d.pubid).to be_nil
    end
  end

  describe "#to_all_parts!" do
    it "drops the edition and marks the identifier as covering all parts" do
      d = described_class.new(content: "IALA S1070 Ed 2.0", type: "IALA", primary: true)
      d.to_all_parts!
      expect(d.pubid.all_parts).to be true
      expect(d.pubid.edition).to be_nil
      expect(d.content).to eq "IALA S1070"
    end

    it "is a safe no-op when pubid is nil" do
      d = described_class.new(type: "IALA")
      expect { d.to_all_parts! }.not_to raise_error
      expect(d.pubid).to be_nil
    end
  end

  describe "integration via ItemData" do
    let(:yaml) do
      <<~YAML
        ---
        id: S1070-2.0
        type: standard
        docidentifier:
        - content: IALA S1070 Ed 2.0
          type: IALA
          primary: true
      YAML
    end

    it "#to_most_recent_reference strips the edition without raising" do
      item = Relaton::Iala::Item.from_yaml(yaml)
      recent = nil
      expect { recent = item.to_most_recent_reference }.not_to raise_error
      expect(recent.docidentifier.first.content).to eq "IALA S1070"
    end

    it "#to_all_parts strips the edition without raising" do
      item = Relaton::Iala::Item.from_yaml(yaml)
      all = nil
      expect { all = item.to_all_parts }.not_to raise_error
      expect(all.docidentifier.first.content).to eq "IALA S1070"
    end
  end
end
