RSpec.describe Relaton::Gost::Processor do
  it "registers with the expected shape" do
    p = described_class.new
    expect(p.short).to eq :relaton_gost
    expect(p.prefix).to eq "GOST"
    expect(p.idtype).to eq "GOST"
  end

  it "matches GOST prefixes (Latin and Cyrillic)" do
    p = described_class.new
    expect(p.defaultprefix.match?("GOST R 34.12-2015")).to be_truthy
    expect(p.defaultprefix.match?("GOST 14946-82")).to be_truthy
    expect(p.defaultprefix.match?("ГОСТ Р 34.11-94")).to be_truthy
    expect(p.defaultprefix.match?("ISO/IEC 12345")).to be_falsey
  end

  it "does not swallow longer tokens that merely start with GOST" do
    p = described_class.new
    expect(p.defaultprefix.match?("GOSTA 1")).to be_falsey
    expect(p.defaultprefix.match?("GOSTAK 1")).to be_falsey
  end
end
