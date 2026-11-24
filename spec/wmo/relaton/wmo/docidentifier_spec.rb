RSpec.describe Relaton::Wmo::Docidentifier do
  it "soft-parses a canonical WMO id and keeps its pubid" do
    d = described_class.new(content: "WMO-No. 8", type: "WMO", primary: true)
    expect(d.pubid).to be_a(Pubid::Wmo::Identifier)
    expect(d.pubid.to_s).to eq("WMO-No. 8")
  end

  it "keeps a non-WMO string as plain content" do
    d = described_class.new(content: "Guide to Instruments and Methods",
                            type: "WMO")
    expect(d.pubid).to be_nil
    expect(d.content).to eq("Guide to Instruments and Methods")
  end

  it "round-trips the four series heads" do
    ["WMO-No. 8", "WMO/TD-No. 1551", "JCOMM Technical Report No. 5",
     "GAW Report No. 234"].each do |id|
      d = described_class.new(content: id, type: "WMO")
      expect(d.pubid.to_s).to eq(id)
    end
  end

  it "keeps the mutation hooks as no-ops" do
    d = described_class.new(content: "WMO-No. 8", type: "WMO")
    expect { d.remove_part! }.not_to raise_error
    expect { d.remove_date! }.not_to raise_error
    expect { d.to_all_parts! }.not_to raise_error
    expect(d.content).to eq("WMO-No. 8")
  end
end
