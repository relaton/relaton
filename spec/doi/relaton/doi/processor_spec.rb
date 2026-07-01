require "relaton/doi/processor"

RSpec.describe Relaton::Doi::Processor do
  subject(:processor) { described_class.new }

  describe "#initialize" do
    it "sets short" do
      expect(processor.short).to eq :relaton_doi
    end

    it "sets prefix" do
      expect(processor.prefix).to eq "DOI"
    end

    it "sets idtype" do
      expect(processor.idtype).to eq "DOI"
    end
  end

  describe "defaultprefix" do
    %w[doi:10.1234/foo doi:10.6028/nist.ir.8245].each do |ref|
      it "matches #{ref.inspect}" do
        expect(processor.defaultprefix).to match(ref)
      end
    end

    ["ISO 123", "NIST SP 800-53", "RFC 1234"].each do |ref|
      it "does not match #{ref.inspect}" do
        expect(processor.defaultprefix).not_to match(ref)
      end
    end
  end

  describe "#get" do
    it "delegates to Crossref.get" do
      expect(Relaton::Doi::Crossref).to receive(:get)
        .with("doi:10.1234/foo").and_return(:item)
      expect(processor.get("doi:10.1234/foo", nil, {})).to be :item
    end
  end

  describe "#fetch_data" do
    it "logs unsupported message" do
      expect(Relaton::Doi::Util).to receive(:info).with(
        "This processor does not support fetching data by source name. Use `get` method with DOI instead.",
      )
      processor.fetch_data("doi", output: "dir", format: "xml")
    end
  end

  describe "#from_xml" do
    it "delegates to Bib::Item.from_xml" do
      expect(Relaton::Bib::Item).to receive(:from_xml).with(:xml).and_return(:item)
      expect(processor.from_xml(:xml)).to be :item
    end
  end

  describe "#from_yaml" do
    it "delegates to Bib::Item.from_yaml" do
      expect(Relaton::Bib::Item).to receive(:from_yaml).with(:yaml).and_return(:item)
      expect(processor.from_yaml(:yaml)).to be :item
    end
  end

  describe "#grammar_hash" do
    it "delegates to Doi.grammar_hash" do
      expect(Relaton::Doi).to receive(:grammar_hash).once.and_return("hash123")
      expect(processor.grammar_hash).to eq "hash123"
    end

    it "memoizes the result" do
      expect(Relaton::Doi).to receive(:grammar_hash).once.and_return("hash123")
      2.times { expect(processor.grammar_hash).to eq "hash123" }
    end
  end

  describe "#threads" do
    it "returns 2" do
      expect(processor.threads).to eq 2
    end
  end
end
