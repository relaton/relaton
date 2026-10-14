# frozen_string_literal: true

describe Relaton::Evs::Docidentifier do
  it "backs its content with the parsed pubid" do
    id = described_class.new type: "EVS", content: "EVS-EN 18216:2026"
    expect(id.pubid).to be_a Pubid::Evs::Identifiers::NationalAdoption
    expect(id.content).to eq "EVS-EN 18216:2026"
  end

  it "keeps a value the grammar cannot read verbatim" do
    id = described_class.new type: "EVS", content: "ISBN 978-1-84930-500-2"
    expect(id.pubid).to be_nil
    expect(id.content).to eq "ISBN 978-1-84930-500-2"
  end

  describe "#remove_date!" do
    it "drops the document year" do
      id = described_class.new type: "EVS", content: "EVS-EN 18216:2026"
      id.remove_date!
      expect(id.content).to eq "EVS-EN 18216"
    end

    it "drops the supplement year, not the base document's" do
      id = described_class.new type: "EVS", content: "EVS-EN ISO 9001:2015/A1:2024"
      id.remove_date!
      expect(id.content).to eq "EVS-EN ISO 9001:2015/A1"
    end

    it "no-ops when the content is not an EVS identifier" do
      id = described_class.new type: "EVS", content: "ISBN 978-1-84930-500-2"
      expect { id.remove_date! }.not_to change { id.content }
    end
  end

  describe "#remove_part!" do
    it "drops the part" do
      id = described_class.new type: "EVS", content: "EVS-IEC 62368-1:2020"
      id.remove_part!
      expect(id.content).to eq "EVS-IEC 62368:2020"
    end
  end

  describe "#to_all_parts!" do
    it "wraps the pubid and strips part and date from the content" do
      id = described_class.new type: "EVS", content: "EVS-EN 18216:2026"
      id.to_all_parts!
      expect(id.content).to eq "EVS-EN 18216"
      expect(id.pubid.all_parts?).to be true
      expect(id.pubid.to_s).to eq "EVS-EN 18216 (all parts)"
    end

    it "no-ops on an all-parts identifier" do
      id = described_class.new type: "EVS", content: "EVS-EN 18216:2026"
      id.to_all_parts!
      expect { id.to_all_parts! }.not_to change { id.content }
    end
  end
end
