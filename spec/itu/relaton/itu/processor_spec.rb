# frozen_string_literal: true

require "relaton/itu/processor"

RSpec.describe Relaton::Itu::Processor do
  subject(:processor) { described_class.new }

  describe "#initialize" do
    it "sets short" do
      expect(processor.short).to eq :relaton_itu
    end

    it "sets prefix" do
      expect(processor.prefix).to eq "ITU"
    end

    it "sets defaultprefix" do
      expect(processor.defaultprefix).to eq %r{^ITU\s}
    end

    it "sets idtype" do
      expect(processor.idtype).to eq "ITU"
    end

    it "sets datasets" do
      expect(processor.datasets).to eq %w[itu-r]
    end
  end

  describe "#get" do
    it "delegates to Bibliography.get" do
      item = double("Item")
      allow(Relaton::Itu::Bibliography).to receive(:get).and_return(item)

      result = processor.get("ITU-T A.1", "2024", {})

      expect(Relaton::Itu::Bibliography).to have_received(:get).with("ITU-T A.1", "2024", {})
      expect(result).to eq item
    end
  end

  describe "#fetch_data" do
    it "delegates to DataFetcher.fetch" do
      require "relaton/itu/data_fetcher"
      allow(Relaton::Itu::DataFetcher).to receive(:fetch)

      processor.fetch_data("itu-r", output: "data", format: "yaml")

      expect(Relaton::Itu::DataFetcher).to have_received(:fetch)
        .with("itu-r", output: "data", format: "yaml")
    end
  end

  describe "#from_xml" do
    it "delegates to Item.from_xml" do
      xml = "<bibitem>...</bibitem>"
      item = double("Item")
      allow(Relaton::Itu::Item).to receive(:from_xml).and_return(item)

      result = processor.from_xml(xml)

      expect(Relaton::Itu::Item).to have_received(:from_xml).with(xml)
      expect(result).to eq item
    end
  end

  describe "#from_yaml" do
    it "delegates to Item.from_yaml" do
      yaml = "---\ntitle: Test"
      item = double("Item")
      allow(Relaton::Itu::Item).to receive(:from_yaml).and_return(item)

      result = processor.from_yaml(yaml)

      expect(Relaton::Itu::Item).to have_received(:from_yaml).with(yaml)
      expect(result).to eq item
    end
  end

  describe "#grammar_hash" do
    it "returns an MD5 hex digest string" do
      result = processor.grammar_hash
      expect(result).to be_a String
      expect(result).to match(/\A[0-9a-f]{32}\z/)
    end

    it "delegates to Relaton::Itu.grammar_hash" do
      allow(Relaton::Itu).to receive(:grammar_hash).and_return("a" * 32)

      result = processor.grammar_hash

      expect(Relaton::Itu).to have_received(:grammar_hash)
      expect(result).to eq "a" * 32
    end
  end

  describe "#remove_index_file" do
    it "finds or creates the index and removes the file" do
      index = double("Index")
      allow(Relaton::Index).to receive(:find_or_create).and_return(index)
      allow(index).to receive(:remove_file)

      processor.remove_index_file

      expect(Relaton::Index).to have_received(:find_or_create)
        .with(:itu, url: true, file: "index-v1.yaml")
      expect(index).to have_received(:remove_file)
    end
  end
end
