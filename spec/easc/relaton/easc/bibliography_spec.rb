RSpec.describe Relaton::Easc::Bibliography do
  it "fetches a ПМГ publication by its Cyrillic citation" do
    item = described_class.get("ПМГ 03-2025")

    expect(item).to be_a(Relaton::Easc::ItemData)
    expect(item.docidentifier.first.content).to eq "ПМГ 03-2025"
    expect(item.ext.urn).to eq "urn:easc:pmg:03:2025"
    expect(item.ext.joining_states).to eq %w[АРМ БЕИ КАЗ]
  end

  it "fetches a РМГ publication by its Cyrillic citation" do
    item = described_class.get("РМГ 151-2025")

    expect(item).to be_a(Relaton::Easc::ItemData)
    expect(item.docidentifier.first.content).to eq "РМГ 151-2025"
    expect(item.ext.session).to eq "67МГС"
  end

  it "resolves a Latin transliteration to the canonical Cyrillic record" do
    item = described_class.get("PMG 03-2025")

    expect(item).to be_a(Relaton::Easc::ItemData)
    expect(item.docidentifier.first.content).to eq "ПМГ 03-2025"
  end

  it "returns nil for a code that is not in the index" do
    expect(described_class.get("ПМГ 999-2099")).to be_nil
  end

  it "raises RequestError when an indexed record's data file is missing" do
    expect { described_class.get("ПМГ 99-2000") }
      .to raise_error(Relaton::RequestError, /HTTP 404/)
  end

  it "stamps the fetched date on a returned item" do
    item = described_class.get("ПМГ 03-2025")
    expect(item.fetched).to eq Date.today.to_s
  end
end
