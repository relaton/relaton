require "relaton/ogc/processor"
require "relaton/ogc/data_fetcher"

describe Relaton::Ogc::Processor do
  subject(:processor) { described_class.new }

  it "initializes with correct attributes" do
    expect(processor.short).to eq :relaton_ogc
    expect(processor.prefix).to eq "OGC"
    expect(processor.idtype).to eq "OGC"
    expect(processor.datasets).to eq %w[ogc-naming-authority]
  end

  it "#get delegates to Bibliography" do
    expect(Relaton::Ogc::Bibliography).to receive(:get)
      .with("OGC 19-025r1", nil, {}).and_return(:item)
    expect(processor.get("OGC 19-025r1", nil, {})).to eq :item
  end

  it "#from_xml delegates to Item" do
    expect(Relaton::Ogc::Item).to receive(:from_xml).with("<xml/>").and_return(:item)
    expect(processor.from_xml("<xml/>")).to eq :item
  end

  it "#from_yaml delegates to Item" do
    expect(Relaton::Ogc::Item).to receive(:from_yaml).with("yaml").and_return(:item)
    expect(processor.from_yaml("yaml")).to eq :item
  end

  it "#grammar_hash returns a string" do
    expect(processor.grammar_hash).to be_a String
  end

  it "#fetch_data delegates to DataFetcher" do
    expect(Relaton::Ogc::DataFetcher).to receive(:fetch)
      .with(output: "dir", format: "yaml").and_return(nil)
    processor.fetch_data("ogc-naming-authority", output: "dir", format: "yaml")
  end

  it "#remove_index_file removes the index file" do
    index = double("index")
    expect(Relaton::Index).to receive(:find_or_create)
      .with(:ogc, url: true, file: "#{Relaton::Ogc::INDEXFILE}.yaml")
      .and_return(index)
    expect(index).to receive(:remove_file)
    processor.remove_index_file
  end
end
