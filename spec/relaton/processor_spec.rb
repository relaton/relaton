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
      expect { subject.fetch_data "source", {} }.to raise_error StandardError
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

  context "flavor processors" do
    before { Relaton::Registry.instance }

    shared_examples "common processor methods" do |flavor, namespace, bibmodule|
      let(:processor) { Relaton::Registry.instance.by_type flavor }
      let(:flavor_module) { Object.const_get namespace }
      let(:bibliography) { Object.const_get "#{namespace}::#{bibmodule}" }

      it "get method should call get method of #{flavor}" do
        expect(bibliography).to receive(:get).with("code", nil, {}).and_return :item
        expect(processor.get("code", nil, {})).to eq :item
      end

      it "grammar_hash method should call grammar_hash method of #{flavor}" do
        expect(flavor_module).to receive(:grammar_hash).and_return :hash
        expect(processor.grammar_hash).to eq :hash
      end
    end

    shared_examples "fetch_data method" do |flavor, fetcher, source|
      let(:processor) { Relaton::Registry.instance.by_type flavor }
      let(:fetcher_class) { Object.const_get fetcher }

      it "fetch_data method should call fetch_data method of #{flavor}" do
        expect(fetcher_class).to receive(:fetch).with(output: "dir", format: "bibxml").and_return :item
        expect(processor.fetch_data(source, output: "dir", format: "bibxml")).to eq :item
      end
    end

    shared_examples "from_xml method" do |flavor, parser|
      let(:processor) { Relaton::Registry.instance.by_type flavor }
      let(:parser_class) { Object.const_get parser }

      it "from_xml method should call from_xml method of #{flavor}" do
        expect(parser_class).to receive(:from_xml).with("xml").and_return :item
        expect(processor.from_xml("xml")).to eq :item
      end
    end

    shared_examples "hash_to_bib method" do |flavor, converter, bibitem|
      let(:processor) { Relaton::Registry.instance.by_type flavor }
      let(:converter_class) { Object.const_get converter }
      let(:bibitem_class) { Object.const_get bibitem }

      it "hash_to_bib method should call hash_to_bib method of #{flavor}" do
        expect(converter_class).to receive(:hash_to_bib).with(:hash).and_return title: "title"
        expect(bibitem_class).to receive(:new).with(title: "title").and_return :item
        expect(processor.hash_to_bib(:hash)).to eq :item
      end
    end

    shared_examples "remove_index_file method" do |flavor, file|
      let(:processor) { Relaton::Registry.instance.by_type flavor }

      it "remove index file" do
        index = double "index"
        expect(index).to receive(:remove_file)
        expect(Relaton::Index).to receive(:find_or_create)
          .with(flavor.downcase.to_sym, url: true, file: file).and_return index
        processor.remove_index_file
      end
    end

    context "ETSI processor" do
      it_behaves_like "common processor methods", "ETSI", "RelatonEtsi", "Bibliography"
      it_behaves_like "fetch_data method", "ETSI", "RelatonEtsi::DataFetcher", "etsi-csv"
      it_behaves_like "from_xml method", "ETSI", "RelatonEtsi::XMLParser"
      it_behaves_like "hash_to_bib method", "ETSI", "RelatonEtsi::HashConverter", "RelatonEtsi::BibliographicItem"
      it_behaves_like "remove_index_file method", "ETSI", "index-v1.yaml"
    end

    context "ISBN processor" do
      it_behaves_like "common processor methods", "ISBN", "RelatonIsbn", "OpenLibrary"
      it_behaves_like "from_xml method", "ISBN", "RelatonBib::XMLParser"
      it_behaves_like "hash_to_bib method", "ISBN", "RelatonBib::HashConverter", "RelatonBib::BibliographicItem"
    end
  end
end
