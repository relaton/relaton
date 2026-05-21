# frozen_string_literal: true

require_relative "../../../lib/relaton/w3c/processor"

describe Relaton::W3c::Processor do
  subject(:processor) { described_class.new }

  it "initializes with expected attributes" do
    expect(processor.short).to eq :relaton_w3c
    expect(processor.prefix).to eq "W3C"
    expect(processor.defaultprefix).to eq(%r{^W3C\s})
    expect(processor.idtype).to eq "W3C"
    expect(processor.datasets).to eq %w[w3c-api]
  end

  describe "#defaultprefix" do
    it "matches W3C prefixed strings" do
      expect(processor.defaultprefix).to match("W3C REC-xml-names")
    end

    it "rejects non-W3C strings" do
      expect(processor.defaultprefix).not_to match("ISO 12345")
    end
  end

  describe "#get" do
    it "delegates to Bibliography.get" do
      expect(Relaton::W3c::Bibliography).to receive(:get)
        .with("W3C xml-names", "2020", {}).and_return(:result)
      expect(processor.get("W3C xml-names", "2020", {})).to eq :result
    end
  end

  describe "#fetch_data" do
    it "delegates to DataFetcher.fetch" do
      require_relative "../../../lib/relaton/w3c/data_fetcher"
      expect(Relaton::W3c::DataFetcher).to receive(:fetch)
        .with(output: "dir", format: "yaml").and_return(:result)
      expect(processor.fetch_data("w3c-api", output: "dir", format: "yaml"))
        .to eq :result
    end
  end

  describe "#from_xml" do
    it "delegates to Bibdata.from_xml" do
      expect(processor.from_xml("<bibitem/>")).to be_instance_of Relaton::W3c::ItemData
    end
  end

  describe "#from_yaml" do
    it "delegates to Item.from_yaml" do
      expect(processor.from_yaml({ id: '123' }.to_yaml)).to be_instance_of Relaton::W3c::ItemData
    end
  end

  describe "#grammar_hash" do
    it "returns a 32-char hex string" do
      expect(processor.grammar_hash).to match(/\A[0-9a-f]{32}\z/)
    end

    it "memoizes the result" do
      first = processor.grammar_hash
      expect(processor.grammar_hash).to equal first
    end
  end

  describe "#remove_index_file" do
    it "removes the index file" do
      index = double("index")
      expect(Relaton::Index).to receive(:find_or_create)
        .with(:W3C, url: true, file: "index-v1.yaml").and_return(index)
      expect(index).to receive(:remove_file)
      processor.remove_index_file
    end
  end
end
