require "relaton/jcgm"

RSpec.describe Relaton::Jcgm::Docidentifier do
  subject(:docid) { described_class.new(content: "JCGM 200:2008", type: "JCGM") }

  it "parses its content into a pubid" do
    expect(docid.pubid).to be_a Pubid::Jcgm::Identifier
  end

  it "leaves the pubid nil for content it cannot parse" do
    expect(described_class.new(content: "JCGM 200:2008/Corr:2010").pubid).to be_nil
  end

  it "#remove_date! strips the date" do
    docid.remove_date!
    expect(docid.content).to eq "JCGM 200"
  end

  # A corrigendum exposes its own `date=` but carries nil there — the year
  # lives on `base`, so clearing only the wrapper is a silent no-op.
  it "#remove_date! reaches the base of a corrigendum" do
    corr = described_class.new(content: "JCGM 200:2008 Corrigendum")
    corr.remove_date!
    expect(corr.content).to eq "JCGM 200 Corrigendum"
  end

  it "#remove_part! does not raise" do
    expect { docid.remove_part! }.not_to raise_error
  end

  it "#to_all_parts! strips the date" do
    docid.to_all_parts!
    expect(docid.content).to eq "JCGM 200"
  end

  # A meeting has no form without its date: the renderer reads `date.year`
  # unconditionally, so dropping it raises instead of producing a shorter id.
  # The mutation is rolled back rather than propagated.
  it "leaves a meeting's date alone, because it cannot render without one" do
    meeting = described_class.new(content: "JCGM 11st Meeting (2006)")
    expect { meeting.remove_date! }.not_to raise_error
    expect(meeting.content).to eq "JCGM 11st Meeting (2006)"
    expect(meeting.pubid.date).not_to be_nil
  end

  it "leaves a meeting alone through #to_all_parts! too" do
    meeting = described_class.new(content: "JCGM 11st Meeting (2006)")
    expect { meeting.to_all_parts! }.not_to raise_error
    expect(meeting.content).to eq "JCGM 11st Meeting (2006)"
  end

  it "leaves a dateless identifier alone" do
    bare = described_class.new(content: "JCGM GUM")
    bare.remove_date!
    expect(bare.content).to eq "JCGM GUM"
  end

  context "when the pubid is nil" do
    subject(:docid) { described_class.new(content: "JCGM 200:2008/Corr:2010") }

    it "no-ops instead of raising" do
      expect { docid.remove_part! }.not_to raise_error
      expect { docid.remove_date! }.not_to raise_error
      expect { docid.to_all_parts! }.not_to raise_error
      expect(docid.content).to eq "JCGM 200:2008/Corr:2010"
    end
  end

  # `ItemData` broadcasts to `ext.structuredidentifier` as well, and JCGM's
  # descends from Lutaml::Model::Serializable rather than
  # Bib::StructuredIdentifier, so the methods were absent there — a
  # NoMethodError, not a NotImplementedError.
  describe "through Bib::ItemData" do
    def item(name)
      Relaton::Jcgm::Item.from_yaml File.read(
        File.join(__dir__, "..", "..", "fixtures", "static", "jcgm", name),
      )
    end

    it "#to_all_parts no longer raises" do
      expect(item("gum.yaml").to_all_parts.docidentifier.first.content).to eq "JCGM GUM"
    end

    it "#to_most_recent_reference no longer raises" do
      expect(item("200-2008.yaml").to_most_recent_reference.docidentifier.first.content)
        .to eq "JCGM 200"
    end
  end
end

RSpec.describe Relaton::Jcgm::StructuredIdentifier do
  subject(:si) { described_class.new(docnumber: "200", part: "1") }

  it "#remove_part! clears the part" do
    si.remove_part!
    expect(si.part).to be_nil
    expect(si.docnumber).to eq "200"
  end

  # JCGM structured identifiers carry no date field; the year lives on the
  # docidentifier's pubid.
  it "#remove_date! is a deliberate no-op" do
    expect { si.remove_date! }.not_to raise_error
    expect(si.docnumber).to eq "200"
  end

  it "#to_all_parts! clears the part" do
    si.to_all_parts!
    expect(si.part).to be_nil
  end
end
