RSpec.describe Relaton::Iala::Ext do
  let(:ext) do
    described_class.new(
      doctype: Relaton::Iala::Doctype.new(content: "standard"),
      flavor: "iala",
      urn: "urn:mrn:iala:pub:s1070:ed2.0",
      webpage: "https://www.iala.int/product/s1070/",
      committee: "DTEC",
      normative: "Nor",
      supersedes: ["IALA S1070 Ed 1.0"],
    )
  end

  it "round-trips the IALA-specific fields through YAML" do
    parsed = described_class.from_yaml(ext.to_yaml)
    expect(parsed.urn).to eq "urn:mrn:iala:pub:s1070:ed2.0"
    expect(parsed.webpage).to eq "https://www.iala.int/product/s1070/"
    expect(parsed.committee).to eq "DTEC"
    expect(parsed.normative).to eq "Nor"
    expect(parsed.supersedes.map(&:to_s)).to eq ["IALA S1070 Ed 1.0"]
    expect(parsed.doctype.content).to eq "standard"
  end

  # XML rendering of a bare Ext with a doctype hits an upstream lutaml quirk
  # that does not occur when the Ext is embedded in an Item (same issue OIML
  # documents in its ext_spec). Skip the XML assertion on the bare Ext; the
  # full document XML round-trip is covered by processor-level specs.
  it "serialises the IALA-specific fields (sans doctype) to XML" do
    fields_only = described_class.new(
      flavor: "iala",
      urn: "urn:mrn:iala:pub:s1070:ed2.0",
      webpage: "https://www.iala.int/product/s1070/",
      committee: "DTEC",
      normative: "Nor",
      supersedes: ["IALA S1070 Ed 1.0"],
    )
    xml = fields_only.to_xml
    expect(xml).to include "<urn>urn:mrn:iala:pub:s1070:ed2.0</urn>"
    expect(xml).to include "<webpage>https://www.iala.int/product/s1070/</webpage>"
    expect(xml).to include "<committee>DTEC</committee>"
    expect(xml).to include "<normative>Nor</normative>"
    expect(xml).to include "<supersedes>IALA S1070 Ed 1.0</supersedes>"
  end
end
