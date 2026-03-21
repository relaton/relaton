require "relaton/bipm/processor"

describe Relaton::Bipm::Processor do
  it "#intialize" do
    expect(subject.instance_variable_get(:@short)).to eq :relaton_bipm
    expect(subject.instance_variable_get(:@prefix)).to eq "BIPM"
    expect(subject.instance_variable_get(:@defaultprefix)).to eq %r{^(?:BIPM|CCTF|CCDS|CGPM|CIPM|JCRB|JCGM)(?!\w)}
    expect(subject.instance_variable_get(:@idtype)).to eq "BIPM"
    expect(subject.instance_variable_get(:@datasets)).to eq %w[bipm-data-outcomes bipm-si-brochure rawdata-bipm-metrologia]
  end

  it "#get" do
    expect(Relaton::Bipm::Bibliography).to receive(:get).with("19115", "2014", {})
    subject.get "19115", "2014", {}
  end

  it "#fetch_data" do
    df = instance_double Relaton::Bipm::DataFetcher
    expect(df).to receive(:fetch).with("bipm-data-outcomes")
    expect(Relaton::Bipm::DataFetcher).to receive(:new).with("output", "xml").and_return df
    subject.fetch_data "bipm-data-outcomes", output: "output", format: "xml"
  end

  it "#from_xml" do
    expect(Relaton::Bipm::Item).to receive(:from_xml).with("<xml></xml>")
    subject.from_xml "<xml></xml>"
  end

  it "#from_yaml" do
    expect(Relaton::Bipm::Item).to receive(:from_yaml).with("---\nkey: value\n")
    subject.from_yaml "---\nkey: value\n"
  end

  it "#grammar_hash" do
    expect(subject.grammar_hash).to be_a String
  end

  it "#remove_index_file" do
    index = instance_double Relaton::Index::Type
    expect(Relaton::Index).to receive(:find_or_create)
      .with(:bipm, url: true, file: Relaton::Bipm::INDEXFILE)
      .and_return index
    expect(index).to receive(:remove_file)
    subject.remove_index_file
  end
end
