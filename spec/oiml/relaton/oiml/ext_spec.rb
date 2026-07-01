RSpec.describe Relaton::Oiml::Ext do
  let(:ext) do
    described_class.new(
      doctype: Relaton::Oiml::Doctype.new(content: "recommendation"),
      flavor: "oiml",
      scope: "Applies to volumetric containers.",
      quantity: "Volume",
      measuring_instrument: "Volumetric container",
      focus_area: "Trade",
      sustainability_framework: "People",
      doi: "10.63493/r138.2007.en",
    )
  end

  it "round-trips the OIML-specific fields through YAML" do
    parsed = described_class.from_yaml(ext.to_yaml)
    expect(parsed.scope).to eq "Applies to volumetric containers."
    expect(parsed.quantity).to eq "Volume"
    expect(parsed.measuring_instrument).to eq "Volumetric container"
    expect(parsed.focus_area).to eq "Trade"
    expect(parsed.sustainability_framework).to eq "People"
    expect(parsed.doi).to eq "10.63493/r138.2007.en"
    expect(parsed.doctype.content).to eq "recommendation"
  end

  # Rendering a bare Ext that carries a `doctype` element hits an upstream
  # relaton-bib/lutaml quirk (Relaton::Bib::Ext has the same issue) that does
  # not occur when the Ext is embedded in an Item — see the full-document XML
  # round-trip in processor_spec.rb. Here we isolate the OIML-specific fields.
  let(:fields_only) do
    described_class.new(
      flavor: "oiml",
      scope: "Applies to volumetric containers.",
      quantity: "Volume",
      measuring_instrument: "Volumetric container",
      focus_area: "Trade",
      sustainability_framework: "People",
      doi: "10.63493/r138.2007.en",
    )
  end

  it "does not advertise a flavor schema version (no OIML model yet)" do
    expect(fields_only.schema_version).to be_nil
    expect(fields_only.to_xml).not_to include "schema-version"
  end

  it "serialises the OIML-specific fields to XML" do
    xml = fields_only.to_xml
    expect(xml).to include "<scope>Applies to volumetric containers.</scope>"
    expect(xml).to include "<quantity>Volume</quantity>"
    expect(xml).to include "<measuring_instrument>Volumetric container</measuring_instrument>"
    expect(xml).to include "<focus_area>Trade</focus_area>"
    expect(xml).to include "<sustainability_framework>People</sustainability_framework>"
    expect(xml).to include "<doi>10.63493/r138.2007.en</doi>"
  end

  it "round-trips the OIML-specific fields through XML" do
    parsed = described_class.from_xml(fields_only.to_xml)
    expect(parsed.scope).to eq "Applies to volumetric containers."
    expect(parsed.doi).to eq "10.63493/r138.2007.en"
  end
end
