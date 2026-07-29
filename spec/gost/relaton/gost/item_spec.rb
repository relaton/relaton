RSpec.describe Relaton::Gost::Item do
  let(:hash) do
    {
      "id" => "GOST R 34.12-2015",
      "type" => "standard",
      "title" => [{
        "language" => "eng",
        "content" => "Information technology — Cryptographic data security — Block cipher",
        "type" => "main",
      }],
      "docidentifier" => [{
        "content" => "GOST R 34.12-2015",
        "type" => "GOST",
        "primary" => true,
      }],
      "ext" => {
        "doctype" => { "content" => "national" },
        "flavor" => "gost",
        "urn" => "urn:gost:std:r:34.12:2015",
        "webpage" => "https://www.gost.ru/portal/gost/home/standarts/catalognational",
      },
    }
  end

  it "round-trips GOST ext fields through YAML" do
    item = described_class.from_hash(hash)
    yaml = item.to_yaml
    restored = described_class.from_yaml(yaml)

    expect(restored.ext.urn).to eq "urn:gost:std:r:34.12:2015"
    expect(restored.ext.doctype.content).to eq "national"
    expect(yaml).to include("urn:gost:std:r:34.12:2015")
  end

  it "preserves the GOST citation form in docidentifier.content" do
    item = described_class.from_hash(hash)
    expect(item.docidentifier.first.content).to eq "GOST R 34.12-2015"
  end

  it "uses Relaton::Gost::Ext for the ext attribute" do
    item = described_class.from_hash(hash)
    expect(item.ext).to be_a(Relaton::Gost::Ext)
  end

  it "is aliased as Bibitem and Bibdata" do
    expect(Relaton::Gost::Bibitem).to be < Relaton::Gost::Item
    expect(Relaton::Gost::Bibdata).to be < Relaton::Gost::Item
  end

  context "with an interstate (GOST) item" do
    let(:inter_hash) do
      {
        "id" => "GOST 14946-82",
        "type" => "standard",
        "title" => [{
          "language" => "eng",
          "content" => "Cylindrical helical compression springs",
          "type" => "main",
        }],
        "docidentifier" => [{
          "content" => "GOST 14946-82",
          "type" => "GOST",
          "primary" => true,
        }],
        "ext" => {
          "doctype" => { "content" => "interstate" },
          "flavor" => "gost",
          "urn" => "urn:gost:std:14946:82",
        },
      }
    end

    it "round-trips the interstate citation form" do
      item = described_class.from_hash(inter_hash)
      restored = described_class.from_yaml(item.to_yaml)
      expect(restored.docidentifier.first.content).to eq "GOST 14946-82"
      expect(restored.ext.doctype.content).to eq "interstate"
    end
  end
end
