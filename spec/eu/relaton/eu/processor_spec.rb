describe Relaton::Eu::Processor do
  subject(:processor) { described_class.new }

  it "routes the EU prefix" do
    expect(processor.prefix).to eq "EU"
    expect(processor.prefixes).to eq ["EU"]
    expect(processor.defaultprefix).to match "EU Regulation 1227/2011"
  end

  it "keys the Db cache with Pubid::Eu" do
    expect(processor.pubid_class).to be Pubid::Eu::Identifier
    key = processor.cache_key("EU Regulation 1227/2011", nil, {})
    expect(key.to_hash).to eq("_type" => "pubid:eu:regulation", "number" => "1227",
                              "year" => "2011")
  end

  it "has the eu-cellar dataset" do
    expect(processor.datasets).to eq %w[eu-cellar eu-cellar-updates]
  end

  it "hands get to the Bibliography" do
    expect(Relaton::Eu::Bibliography).to receive(:get)
      .with("EU Regulation 1227/2011", nil, {}).and_return(:item)
    expect(processor.get("EU Regulation 1227/2011", nil, {})).to be :item
  end

  it "hands fetch_data to the DataFetcher" do
    expect(Relaton::Eu::DataFetcher).to receive(:fetch)
      .with("eu-cellar", output: "data", format: "yaml")
    processor.fetch_data "eu-cellar", output: "data", format: "yaml"
  end

  context "a document" do
    let(:yaml) { File.read "fixtures/data/eu-regulation-1227-2011.yaml", encoding: "UTF-8" }

    it "reads YAML" do
      item = processor.from_yaml yaml
      expect(item).to be_a Relaton::Bib::ItemData
      expect(item.docidentifier.first.content).to eq "EU Regulation 1227/2011"
    end

    it "reads XML" do
      xml = processor.from_yaml(yaml).to_xml(bibdata: true)
      expect(processor.from_xml(xml).docidentifier.first.content)
        .to eq "EU Regulation 1227/2011"
    end
  end

  it "hashes the gem version for the grammar" do
    expect(processor.grammar_hash).to eq Digest::MD5.hexdigest(Relaton::VERSION)
  end
end
