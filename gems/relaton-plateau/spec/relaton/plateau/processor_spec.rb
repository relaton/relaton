require "relaton/plateau/data_fetcher"

RSpec.describe Relaton::Plateau::Processor do
  subject { described_class.new }

  it "initializes" do
    expect(subject.instance_variable_get(:@short)).to eq :relaton_plateau
    expect(subject.instance_variable_get(:@prefix)).to eq "PLATEAU"
    expect(subject.instance_variable_get(:@defaultprefix)).to eq(/^PLATEAU\s/)
    expect(subject.idtype).to eq "PLATEAU"
    expect(subject.instance_variable_get(:@datasets)).to eq %w[plateau-handbooks plateau-technical-reports]
  end

  it "get" do
    expect(Relaton::Plateau::Bibliography).to receive(:get).with("code", "date", {}).and_return :item
    expect(subject.get("code", "date", {})).to eq :item
  end

  it "fetch_data" do
    expect(Relaton::Plateau::DataFetcher).to receive(:fetch).with("plateau-handbooks", output: "data").and_return nil
    subject.fetch_data("plateau-handbooks", output: "data")
  end

  it "from_xml" do
    expect(Relaton::Plateau::Item).to receive(:from_xml).with("<xml/>").and_return :item
    expect(subject.from_xml("<xml/>")).to eq :item
  end

  it "from_yaml" do
    expect(Relaton::Plateau::Item).to receive(:from_yaml).with("yaml").and_return :item
    expect(subject.from_yaml("yaml")).to eq :item
  end

  it "grammar_hash" do
    expect(subject.grammar_hash).to match(/^[0-9a-f]{32}$/)
  end

  it "threads" do
    expect(subject.threads).to eq 3
  end

  it "remove_index_file" do
    index = double("index")
    expect(Relaton::Index).to receive(:find_or_create).with(
      :plateau, url: true, file: "index-v1.yaml"
    ).and_return index
    expect(index).to receive(:remove_file)
    subject.remove_index_file
  end
end
