require "relaton/iala"

RSpec.describe Relaton::Iala::Item do
  let(:yaml) do
    <<~YAML
      ---
      id: S1070-2.0
      type: standard
      title:
      - language: eng
        content: Information Services
        type: main
      docidentifier:
      - content: IALA S1070 Ed 2.0
        type: IALA
        primary: true
      ext:
        doctype:
          content: standard
        flavor: iala
        urn: urn:mrn:iala:pub:s1070:ed2.0
        webpage: https://www.iala.int/product/s1070/
        committee: DTEC
    YAML
  end

  it "round-trips the IALA ext fields through YAML" do
    item = described_class.from_yaml(yaml)
    expect(item.ext.urn).to eq "urn:mrn:iala:pub:s1070:ed2.0"
    expect(item.ext.webpage).to eq "https://www.iala.int/product/s1070/"
    expect(item.ext.committee).to eq "DTEC"

    restored = described_class.from_yaml(item.to_yaml)
    expect(restored.ext.urn).to eq "urn:mrn:iala:pub:s1070:ed2.0"
    expect(restored.ext.webpage).to eq "https://www.iala.int/product/s1070/"
    expect(restored.ext.committee).to eq "DTEC"
  end

  it "exposes the typed Ext class" do
    item = described_class.from_yaml(yaml)
    expect(item.ext).to be_a(Relaton::Iala::Ext)
  end
end
