RSpec.describe Relaton::Easc::Ext do
  let(:ext) do
    described_class.new(
      doctype: Relaton::Easc::Doctype.new(content: "rmg"),
      flavor: "easc",
      urn: "urn:easc:rmg:151:2025",
      webpage: "https://mgscatalog.by/katalogstand_detail.php?UrlRN=478357",
      session: "67МГС",
      developer: "Российская Федерация",
      joining_states: ["АРМ", "БЕИ", "КЫР", "ТАД", "РОФ"],
      assigned_to: "МТК 536 Методология межгосударственной стандартизации",
    )
  end

  it "round-trips the EASC-specific fields through YAML" do
    parsed = described_class.from_yaml(ext.to_yaml)
    expect(parsed.urn).to eq "urn:easc:rmg:151:2025"
    expect(parsed.webpage)
      .to eq "https://mgscatalog.by/katalogstand_detail.php?UrlRN=478357"
    expect(parsed.session).to eq "67МГС"
    expect(parsed.developer).to eq "Российская Федерация"
    expect(parsed.joining_states.map(&:to_s)).to eq %w[АРМ БЕИ КЫР ТАД РОФ]
    expect(parsed.assigned_to).to eq "МТК 536 Методология межгосударственной стандартизации"
    expect(parsed.doctype.content).to eq "rmg"
  end

  it "round-trips a ПМГ ext" do
    pmg = described_class.new(
      doctype: Relaton::Easc::Doctype.new(content: "pmg"),
      flavor: "easc",
      urn: "urn:easc:pmg:v:31:2001",
    )
    parsed = described_class.from_yaml(pmg.to_yaml)
    expect(parsed.doctype.content).to eq "pmg"
    expect(parsed.urn).to eq "urn:easc:pmg:v:31:2001"
  end
end
