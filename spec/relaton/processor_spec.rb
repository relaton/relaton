module Relaton
  class TestProcessor < Relaton::Processor
    def initialize; end
  end
end

RSpec.describe Relaton::Processor do
  it "initialize should be implemented" do
    expect { Relaton::Processor.new }.to raise_error StandardError
  end

  context "instance of processor" do
    subject { Relaton::TestProcessor.new }

    it "get method should be implemented" do
      expect { subject.get "code", nil, {} }.to raise_error StandardError
    end

    it "fetch_data method should be implemented" do
      expect { subject.fetch_data "cource", {} }.to raise_error StandardError
    end

    it "from_xml method should be implemented" do
      expect { subject.from_xml "" }.to raise_error StandardError
    end

    it "hash_to_bib method should be implemented" do
      expect { subject.hash_to_bib({}) }.to raise_error StandardError
    end

    it "grammar_hash method should be implemented" do
      expect { subject.grammar_hash }.to raise_error StandardError
    end
  end

  context "ETSI processor" do
    before { Relaton::Registry.instance }
    let(:processor) { Relaton::Registry.instance.by_type "ETSI" }

    it "get method should call get method of ETSI" do
      expect(RelatonEtsi::Bibliography).to receive(:get).with("code", nil, {}).and_return :item
      expect(processor.get "code", nil, {}).to eq :item
    end

    it "fetch_data method should call fetch_data method of ETSI" do
      expect(RelatonEtsi::DataFetcher).to receive(:fetch).with(output: "dir", format: "bibxml").and_return :item
      expect(processor.fetch_data "etsi-csv", output: "dir", format: "bibxml").to eq :item
    end

    it "from_xml method should call from_xml method of ETSI" do
      expect(RelatonEtsi::XMLParser).to receive(:from_xml).with("xml").and_return :item
      expect(processor.from_xml "xml").to eq :item
    end

    it "hash_to_bib method should call hash_to_bib method of ETSI" do
      expect(RelatonEtsi::HashConverter).to receive(:hash_to_bib).with(:hash).and_return title: "title"
      expect(RelatonEtsi::BibliographicItem).to receive(:new).with(title: "title").and_return :item
      expect(processor.hash_to_bib(:hash)).to eq :item
    end

    it "grammar_hash method should call grammar_hash method of ETSI" do
      expect(RelatonEtsi).to receive(:grammar_hash).and_return :hash
      expect(processor.grammar_hash).to eq :hash
    end

    it "remove index file" do
      index = double "index"
      expect(index).to receive(:remove_file)
      expect(Relaton::Index).to receive(:find_or_create).with(:etsi, url: true, file: "index-v1.yaml").and_return index
      processor.remove_index_file
    end
  end
end
