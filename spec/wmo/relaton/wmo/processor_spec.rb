RSpec.describe Relaton::Wmo::Processor do
  it "registers with the expected shape" do
    p = described_class.new
    expect(p.short).to eq :relaton_wmo
    expect(p.prefix).to eq "WMO"
  end

  it "matches the series heads via defaultprefix" do
    p = described_class.new
    expect(p.defaultprefix.match?("WMO-No. 8")).to be_truthy
    expect(p.defaultprefix.match?("WMO/TD-No. 1551")).to be_truthy
    expect(p.defaultprefix.match?("JCOMM Technical Report No. 5")).to be_truthy
    expect(p.defaultprefix.match?("GAW Report No. 234")).to be_truthy
    expect(p.defaultprefix.match?("ISO/IEC 12345")).to be_falsey
  end

  # A bare S-number is the shared S-100 shape of IHO and WMO: no flavor
  # owns the routing (pubid#469), so the WMO prefix must not claim it.
  it "does not claim the shared S-100 lexical form" do
    p = described_class.new
    expect(p.defaultprefix.match?("S-411")).to be_falsey
  end

  it "routes #get through Bibliography (not back into Db#fetch)" do
    p = described_class.new
    expect(Relaton::Wmo::Bibliography)
      .to receive(:get).with("WMO-No. 8", nil, {}).and_return(:item)
    expect(p.get("WMO-No. 8", nil, {})).to eq :item
  end
end
