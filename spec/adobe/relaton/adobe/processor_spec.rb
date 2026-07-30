RSpec.describe Relaton::Adobe::Processor do
  it "registers with the expected shape" do
    p = described_class.new
    expect(p.short).to eq :relaton_adobe
    expect(p.prefix).to eq "Adobe"
    expect(p.idtype).to eq "Adobe"
  end

  it "matches Adobe prefixes via defaultprefix" do
    p = described_class.new
    expect(p.defaultprefix.match?("Adobe Glyph List")).to be_truthy
    expect(p.defaultprefix.match?("ATN5014")).to be_truthy
    expect(p.defaultprefix.match?("ISO/IEC 12345")).to be_falsey
  end

  it "routes #get through Bibliography (not back into Db#fetch)" do
    p = described_class.new
    expect(Relaton::Adobe::Bibliography)
      .to receive(:get).with("Adobe TN 5014", nil, {}).and_return(:item)
    expect(p.get("Adobe TN 5014", nil, {})).to eq :item
  end
end
