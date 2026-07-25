RSpec.describe Relaton::Easc::Item do
  let(:hash) do
    {
      "id" => "РМГ-151-2025",
      "type" => "standard",
      "title" => [{
        "language" => "rus",
        "content" => "Введение в действие, применение и отмена межгосударственных стандартов",
        "type" => "main",
      }],
      "docidentifier" => [{
        "content" => "РМГ 151-2025",
        "type" => "EASC",
        "primary" => true,
      }],
      "ext" => {
        "doctype" => { "content" => "rmg" },
        "flavor" => "easc",
        "urn" => "urn:easc:rmg:151:2025",
        "webpage" => "https://mgscatalog.by/katalogstand_detail.php?UrlRN=478357",
        "session" => "67МГС",
        "developer" => "Российская Федерация",
      },
    }
  end

  it "round-trips EASC ext fields through YAML" do
    item = described_class.from_hash(hash)
    yaml = item.to_yaml
    restored = described_class.from_yaml(yaml)

    expect(restored.ext.urn).to eq "urn:easc:rmg:151:2025"
    expect(restored.ext.session).to eq "67МГС"
    expect(yaml).to include("urn:easc:rmg:151:2025")
    expect(yaml).to include("67МГС")
  end

  it "preserves the Cyrillic citation in docidentifier.content" do
    item = described_class.from_hash(hash)
    expect(item.docidentifier.first.content).to eq "РМГ 151-2025"
  end

  it "uses Relaton::Easc::Ext for the ext attribute" do
    item = described_class.from_hash(hash)
    expect(item.ext).to be_a(Relaton::Easc::Ext)
  end

  it "is aliased as Bibitem and Bibdata" do
    expect(Relaton::Easc::Bibitem).to be < Relaton::Easc::Item
    expect(Relaton::Easc::Bibdata).to be < Relaton::Easc::Item
  end
end
