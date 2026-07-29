RSpec.describe Relaton::Gost::Ext do
  let(:ext) do
    described_class.new(
      doctype: Relaton::Gost::Doctype.new(content: "national"),
      flavor: "gost",
      urn: "urn:gost:std:r:34.12:2015",
      webpage: "https://www.gost.ru/portal/gost/home/standarts/catalognational",
    )
  end

  it "round-trips the GOST-specific fields through YAML" do
    parsed = described_class.from_yaml(ext.to_yaml)
    expect(parsed.urn).to eq "urn:gost:std:r:34.12:2015"
    expect(parsed.webpage)
      .to eq "https://www.gost.ru/portal/gost/home/standarts/catalognational"
    expect(parsed.doctype.content).to eq "national"
  end

  it "round-trips an interstate (GOST) ext" do
    inter = described_class.new(
      doctype: Relaton::Gost::Doctype.new(content: "interstate"),
      flavor: "gost",
      urn: "urn:gost:std:14946:82",
    )
    parsed = described_class.from_yaml(inter.to_yaml)
    expect(parsed.doctype.content).to eq "interstate"
    expect(parsed.urn).to eq "urn:gost:std:14946:82"
  end
end
