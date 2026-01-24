require "relaton/etsi/processor"
require "relaton/etsi/data_fetcher"

describe Relaton::Etsi::Processor do
  it "#initialize" do
    expect(subject.instance_variable_get(:@short)).to eq :relaton_etsi
    expect(subject.instance_variable_get(:@prefix)).to eq "ETSI"
    expect(subject.instance_variable_get(:@defaultprefix)).to eq %r{^ETSI\s}
    expect(subject.instance_variable_get(:@idtype)).to eq "ETSI"
    expect(subject.instance_variable_get(:@datasets)).to eq %w[etsi-csv]
  end

  it "#get" do
    expect(Relaton::Etsi::Bibliography).to receive(:get).with("ETSI EN 300 175-1", "2023", {})
    subject.get "ETSI EN 300 175-1", "2023", {}
  end

  it "#fetch_data" do
    expect(Relaton::Etsi::DataFetcher).to receive(:fetch).with(output: "output", format: "xml")
    subject.fetch_data "etsi-csv", output: "output", format: "xml"
  end

  it "#from_xml" do
    expect(Relaton::Etsi::Item).to receive(:from_xml).with("<xml></xml>")
    subject.from_xml "<xml></xml>"
  end

  it "#from_yaml" do
    expect(Relaton::Etsi::Item).to receive(:from_yaml).with("---\nkey: value\n")
    subject.from_yaml "---\nkey: value\n"
  end

  it "#grammar_hash" do
    expect(subject.grammar_hash).to be_a String
  end

  it "#remove_index_file" do
    index = double("index")
    expect(Relaton::Index).to receive(:find_or_create)
      .with(:etsi, url: true, file: Relaton::Etsi::INDEX_FILE).and_return(index)
    expect(index).to receive(:remove_file)
    subject.remove_index_file
  end
end
