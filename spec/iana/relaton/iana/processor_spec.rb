require "relaton/iana/processor"

RSpec.describe Relaton::Iana::Processor do
  subject(:processor) { described_class.new }

  describe "#initialize" do
    it "sets short" do
      expect(processor.short).to eq :relaton_iana
    end

    it "sets prefix" do
      expect(processor.prefix).to eq "IANA"
    end

    it "sets defaultprefix" do
      expect(processor.defaultprefix).to eq %r{^IANA\s}
    end

    it "sets idtype" do
      expect(processor.idtype).to eq "IANA"
    end

    it "sets datasets" do
      expect(processor.datasets).to eq %w[iana-registries]
    end
  end

  describe "#get" do
    it "fetches document by code" do
      expect(Relaton::Iana::Bibliography).to receive(:get).with("code", "2020", { option: "value" })
      processor.get("code", "2020", { option: "value" })
    end
  end

  describe "#fetch_data" do
    it "fetches data from source" do
      expect(Relaton::Iana::DataFetcher).to receive(:fetch).with("iana-registries", output: "dir", format: "yaml")
      processor.fetch_data("iana-registries", output: "dir", format: "yaml")
    end
  end

  describe "#from_xml" do
    it "creates item from XML" do
      xml = "<bibitem>...</bibitem>"
      expect(Relaton::Iana::Item).to receive(:from_xml).with(xml)
      processor.from_xml(xml)
    end
  end

  describe "#from_yaml" do
    it "creates item from YAML" do
      yaml = "schema: relaton-iana"
      expect(Relaton::Iana::Item).to receive(:from_yaml).with(yaml)
      processor.from_yaml(yaml)
    end
  end

  describe "#grammar_hash" do
    it "returns grammar hash" do
      expect(Relaton::Iana).to receive(:grammar_hash).and_return("hash")
      expect(processor.grammar_hash).to eq "hash"
    end

    it "memoizes the result" do
      expect(Relaton::Iana).to receive(:grammar_hash).once.and_return("hash")
      2.times { processor.grammar_hash }
    end
  end

  describe "#remove_index_file" do
    it "removes index file" do
      index = double("index")
      expect(Relaton::Index).to receive(:find_or_create)
        .with(:iana, url: true, file: "#{Relaton::Iana::INDEXFILE}.yaml")
        .and_return(index)
      expect(index).to receive(:remove_file)
      processor.remove_index_file
    end
  end
end
