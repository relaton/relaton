require "relaton/xsf/processor"
require "relaton/xsf/data_fetcher"

describe Relaton::Xsf::Processor do
  subject { described_class.new }

  it "has correct attributes" do
    expect(subject.short).to eq :relaton_xsf
    expect(subject.prefix).to eq "XEP"
    expect(subject.defaultprefix).to eq %r{^XEP\s}
    expect(subject.idtype).to eq "XEP"
    expect(subject.datasets).to eq %w[xep-xmpp]
  end

  it "#get" do
    expect(Relaton::Xsf::Bibliography).to receive(:get).with("code", nil, {}).and_return :item
    expect(subject.get("code", nil, {})).to eq :item
  end

  it "#fetch_data" do
    expect(Relaton::Xsf::DataFetcher).to receive(:fetch).with(output: "dir", format: "yaml").and_return :data
    expect(subject.fetch_data("source", output: "dir", format: "yaml")).to eq :data
  end

  it "#from_xml" do
    expect(Relaton::Bib::Item).to receive(:from_xml).with("<xml/>").and_return :item
    expect(subject.from_xml("<xml/>")).to eq :item
  end

  it "#from_yaml" do
    expect(Relaton::Bib::Item).to receive(:from_yaml).with("yaml").and_return :item
    expect(subject.from_yaml("yaml")).to eq :item
  end

  it "#grammar_hash" do
    expect(subject.grammar_hash).to eq Relaton::Xsf.grammar_hash
  end

  it "#remove_index_file" do
    index = double "index"
    expect(Relaton::Index).to receive(:find_or_create).with(
      :xsf, url: true, file: "index-v1.yaml"
    ).and_return index
    expect(index).to receive(:remove_file)
    subject.remove_index_file
  end
end
