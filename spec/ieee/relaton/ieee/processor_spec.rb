require "relaton/ieee/processor"

RSpec.describe Relaton::Ieee::Processor do
  let(:processor) { described_class.new }

  describe "#initialize" do
    it "sets @short" do
      expect(processor.instance_variable_get(:@short)).to eq :relaton_ieee
    end

    it "sets @prefix" do
      expect(processor.instance_variable_get(:@prefix)).to eq "IEEE"
    end

    it "sets @defaultprefix" do
      expect(processor.instance_variable_get(:@defaultprefix)).to eq(
        %r{^(?:(?:(?:ANSI|NACE)/)?IEEE|ANSI|AIEE|ASA|NACE|IRE)\s}
      )
    end

    it "sets @idtype" do
      expect(processor.idtype).to eq "IEEE"
    end

    it "sets @datasets" do
      expect(processor.instance_variable_get(:@datasets)).to eq %w[ieee-rawbib]
    end
  end

  describe "#get" do
    it "calls Bibliography.get" do
      expect(Relaton::Ieee::Bibliography).to receive(:get).with("IEEE 528", "2019", {}).and_return :item
      expect(processor.get("IEEE 528", "2019", {})).to eq :item
    end
  end

  describe "#fetch_data" do
    it "calls DataFetcher.fetch" do
      expect(Relaton::Ieee::DataFetcher).to receive(:fetch).with("ieee-rawbib", output: "data", format: "yaml")
      processor.fetch_data("ieee-rawbib", output: "data", format: "yaml")
    end
  end

  describe "#from_xml" do
    it "calls Item.from_xml" do
      xml = "<bibitem/>"
      expect(Relaton::Ieee::Item).to receive(:from_xml).with(xml).and_return :item
      expect(processor.from_xml(xml)).to eq :item
    end
  end

  describe "#hash_to_bib" do
    it "calls Item.from_yaml" do
      yaml = "---\ntitle: Test"
      expect(Relaton::Ieee::Item).to receive(:from_yaml).with(yaml).and_return :item
      expect(processor.hash_to_bib(yaml)).to eq :item
    end
  end

  describe "#grammar_hash" do
    it "calls Ieee.grammar_hash" do
      expect(Relaton::Ieee).to receive(:grammar_hash).and_return "abc123"
      expect(processor.grammar_hash).to eq "abc123"
    end

    it "memoizes the result" do
      expect(Relaton::Ieee).to receive(:grammar_hash).once.and_return "abc123"
      processor.grammar_hash
      expect(processor.grammar_hash).to eq "abc123"
    end
  end

  describe "#remove_index_file" do
    it "removes the index file" do
      index = double("index")
      expect(Relaton::Index).to receive(:find_or_create).with(
        :ieee, url: true, file: "#{Relaton::Ieee::INDEXFILE}.yaml"
      ).and_return index
      expect(index).to receive(:remove_file)
      processor.remove_index_file
    end
  end
end
