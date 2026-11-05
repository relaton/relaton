describe Relaton::Sae::Processor do
  subject(:processor) { described_class.new }

  it "declares the flavor" do
    expect(processor.short).to eq :relaton_sae
    expect(processor.prefix).to eq "SAE"
    expect(processor.defaultprefix).to match "SAE J3016"
    expect(processor.idtype).to eq "SAE"
    expect(processor.datasets).to eq %w[sae-crossref]
  end

  it "#get delegates to Bibliography.get" do
    expect(Relaton::Sae::Bibliography).to receive(:get).with("SAE J3016",
                                                             "2021", {}).and_return :item
    expect(processor.get("SAE J3016", "2021", {})).to eq :item
  end

  it "#fetch_data delegates to DataFetcher.fetch" do
    require "relaton/sae/data_fetcher"
    expect(Relaton::Sae::DataFetcher).to receive(:fetch).with("sae-crossref",
                                                              output: "dir", format: "xml")
    processor.fetch_data "sae-crossref", output: "dir", format: "xml"
  end

  it "parses a reference into the Db cache key" do
    expect(processor.cache_pubid("SAE J3016:2021")).to be_a Pubid::Sae::Identifier
  end

  it "parses SAE's native edition code into the Db cache key" do
    expect(processor.cache_pubid("SAE J3016_202104").date.month).to eq 4
  end

  it "reads YAML and XML" do
    yaml = File.read "fixtures/data/sae-j3194_201911.yaml", encoding: "UTF-8"
    item = processor.from_yaml yaml
    expect(item).to be_a Relaton::Sae::ItemData
    xml = Relaton::Sae::Bibdata.to_xml item
    expect(processor.from_xml(xml).docidentifier.first.content).to eq "SAE J3194_201911"
  end

  it "hashes Relaton::VERSION as its grammar hash" do
    expect(processor.grammar_hash).to eq Digest::MD5.hexdigest(Relaton::VERSION)
  end

  it "removes its index file" do
    index = instance_double Relaton::Index::Type
    expect(Relaton::Index).to receive(:find_or_create)
      .with(:sae, url: true, file: "#{Relaton::Sae::INDEXFILE}.yaml").and_return index
    expect(index).to receive(:remove_file)
    processor.remove_index_file
  end
end
