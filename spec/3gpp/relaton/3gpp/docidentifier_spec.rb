# frozen_string_literal: true

RSpec.describe Relaton::ThreeGpp::Docidentifier do
  describe "#initialize / #content=" do
    it "parses content into a Pubid::Tgpp identifier" do
      docid = described_class.new content: "3GPP TS 29.198-04-1:REL-5/5.0.0"
      expect(docid.pubid).to be_a ::Pubid::Tgpp::Identifiers::TechnicalSpecification
      expect(docid.pubid.number).to eq "29.198"
      expect(docid.pubid.parts).to eq %w[04 1]
      expect(docid.pubid.release).to eq "REL-5"
      expect(docid.pubid.version).to eq "5.0.0"
      expect(docid.content).to eq "3GPP TS 29.198-04-1:REL-5/5.0.0"
    end

    it "keeps the document type as the identifier's class" do
      expect(described_class.new(content: "3GPP TR 00.01U:UMTS/3.0.0").pubid)
        .to be_a ::Pubid::Tgpp::Identifiers::TechnicalReport
    end

    it "accepts a parsed Pubid object via the :pubid keyword" do
      pubid = ::Pubid::Tgpp::Identifier.parse "TS 23.207:REL-4/1.0.0"
      docid = described_class.new pubid: pubid
      expect(docid.pubid).to equal pubid
      # Rendered WITH the publisher token, the form relaton stores.
      expect(docid.content).to eq "3GPP TS 23.207:REL-4/1.0.0"
    end

    it "leaves pubid nil on unparseable content (soft rescue, no raise)" do
      docid = nil
      expect { docid = described_class.new content: "not an identifier" }
        .not_to raise_error
      expect(docid.pubid).to be_nil
      expect(docid.content).to eq "not an identifier"
    end

    it "leaves pubid nil when content is empty" do
      expect(described_class.new(content: "").pubid).to be_nil
    end
  end

  describe "#remove_part!" do
    it "clears the parts and re-renders the content" do
      docid = described_class.new content: "3GPP TS 29.198-04-1:REL-5/5.0.0"
      docid.remove_part!
      expect(docid.pubid.parts).to be_empty
      expect(docid.content).to eq "3GPP TS 29.198:REL-5/5.0.0"
    end

    it "is a safe no-op when pubid is nil" do
      docid = described_class.new content: "not an identifier"
      expect { docid.remove_part! }.not_to raise_error
      expect(docid.content).to eq "not an identifier"
    end
  end

  describe "#remove_date!" do
    # 3GPP carries no date; `release` and `version` are its version
    # discriminators, so both go.
    it "clears the release and the version, and re-renders" do
      docid = described_class.new content: "3GPP TS 23.207:REL-4/1.0.0"
      docid.remove_date!
      expect(docid.pubid.release).to be_nil
      expect(docid.pubid.version).to be_nil
      expect(docid.content).to eq "3GPP TS 23.207"
    end

    it "is a safe no-op when pubid is nil" do
      docid = described_class.new content: "not an identifier"
      expect { docid.remove_date! }.not_to raise_error
    end
  end

  describe "#to_all_parts!" do
    it "drops the parts, the release and the version" do
      docid = described_class.new content: "3GPP TS 29.198-04-1:REL-5/5.0.0"
      docid.to_all_parts!
      expect(docid.content).to eq "3GPP TS 29.198"
    end

    it "is a safe no-op when pubid is nil" do
      docid = described_class.new content: "not an identifier"
      expect { docid.to_all_parts! }.not_to raise_error
    end
  end

  describe "the rendered form" do
    # Pubid::Tgpp#to_s omits the "3GPP " token by default, because that is the
    # form the index id takes. The stored docidentifier content keeps it, so
    # every re-render must opt back in.
    it "keeps the 3GPP prefix after a mutation" do
      docid = described_class.new content: "3GPP TS 23.207:REL-4/1.0.0"
      docid.remove_date!
      expect(docid.content).to start_with "3GPP "
    end
  end

  describe "integration through ItemData" do
    # The regression this class exists to fix: Bib::Docidentifier raises
    # NotImplementedError from all three mutators, and ItemData broadcasts to
    # every docidentifier, so both of these raised on any 3GPP item.
    subject(:item) do
      Relaton::ThreeGpp::Item.from_yaml <<~YAML
        docidentifier:
        - content: 3GPP TS 29.198-04-1:REL-5/5.0.0
          type: 3GPP
          primary: true
      YAML
    end

    it "instantiates the flavor Docidentifier, not the base class" do
      expect(item.docidentifier.first).to be_a described_class
    end

    # Both return a deep_clone and leave the receiver alone, so assert on
    # what comes back.
    it "#to_most_recent_reference strips the release and version" do
      recent = nil
      expect { recent = item.to_most_recent_reference }.not_to raise_error
      expect(recent.docidentifier.first.content).to eq "3GPP TS 29.198-04-1"
    end

    it "#to_all_parts strips the parts too" do
      all_parts = nil
      expect { all_parts = item.to_all_parts }.not_to raise_error
      expect(all_parts.docidentifier.first.content).to eq "3GPP TS 29.198"
    end
  end
end
