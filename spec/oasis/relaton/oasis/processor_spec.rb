# frozen_string_literal: true

require "relaton/oasis/processor"

RSpec.describe Relaton::Oasis::Processor do
  subject(:processor) { described_class.new }

  it "initializes attributes" do
    expect(processor.short).to eq :relaton_oasis
    expect(processor.prefix).to eq "OASIS"
    expect(processor.defaultprefix).to eq(%r{^OASIS\s})
    expect(processor.idtype).to eq "OASIS"
    expect(processor.datasets).to eq %w[oasis-open]
  end

  describe "#get" do
    it "delegates to Bibliography.get" do
      expect(Relaton::Oasis::Bibliography).to receive(:get)
        .with("code", "2020", {}).and_return(:item)
      expect(processor.get("code", "2020", {})).to eq :item
    end
  end

  describe "#fetch_data" do
    it "delegates to DataFetcher.fetch" do
      require "relaton/oasis/data_fetcher"
      expect(Relaton::Oasis::DataFetcher).to receive(:fetch)
        .with(output: "dir", format: "yaml").and_return(:result)
      opts = { output: "dir", format: "yaml" }
      result = processor.fetch_data("oasis-open", **opts)
      expect(result).to eq :result
    end
  end

  describe "#from_xml" do
    it "returns an ItemData instance" do
      xml = File.read("fixtures/bibitem.xml")
      item = processor.from_xml(xml)
      expect(item).to be_instance_of Relaton::Oasis::ItemData
    end
  end

  describe "#from_yaml" do
    it "returns an ItemData instance" do
      yaml = File.read("fixtures/item.yaml")
      item = processor.from_yaml(yaml)
      expect(item).to be_instance_of Relaton::Oasis::ItemData
    end
  end

  describe "#grammar_hash" do
    it "returns a non-empty string" do
      hash = processor.grammar_hash
      expect(hash).to be_a String
      expect(hash).not_to be_empty
    end
  end

  describe "#remove_index_file" do
    it "calls remove_file on the index" do
      index = double("index")
      expect(Relaton::Index).to receive(:find_or_create)
        .with(:oasis, file: "index-v1.yaml").and_return(index)
      expect(index).to receive(:remove_file)
      processor.remove_index_file
    end
  end
end
