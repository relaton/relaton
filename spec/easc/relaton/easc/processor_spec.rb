RSpec.describe Relaton::Easc::Processor do
  it "registers with the expected shape" do
    p = described_class.new
    expect(p.short).to eq :relaton_easc
    expect(p.prefix).to eq "EASC"
    expect(p.idtype).to eq "EASC"
  end

  it "matches Cyrillic EASC prefixes" do
    p = described_class.new
    expect(p.defaultprefix.match?("ПМГ 03-2025")).to be_truthy
    expect(p.defaultprefix.match?("ПМГ В 31-2001")).to be_truthy
    expect(p.defaultprefix.match?("РМГ 151-2025")).to be_truthy
    expect(p.defaultprefix.match?("ГОСТ 14946-82")).to be_falsey
  end

  it "matches Latin transliterations" do
    p = described_class.new
    expect(p.defaultprefix.match?("PMG 03-2025")).to be_truthy
    expect(p.defaultprefix.match?("RMG 151-2025")).to be_truthy
  end
end
