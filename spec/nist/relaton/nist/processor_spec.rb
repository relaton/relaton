require "relaton/nist/processor"
require "relaton/nist/data_fetcher"

RSpec.describe Relaton::Nist::Processor do
  subject(:processor) { described_class.new }

  describe "#initialize" do
    it "sets short" do
      expect(processor.short).to eq :relaton_nist
    end

    it "sets prefix" do
      expect(processor.prefix).to eq "NIST"
    end

    it "sets idtype" do
      expect(processor.idtype).to eq "NIST"
    end

    it "sets datasets" do
      expect(processor.datasets).to eq %w[nist-tech-pubs]
    end
  end

  describe "defaultprefix" do
    %w[NIST\ SP\ 800-53 FIPS\ 140 NISTIR\ 8200 NBS\ foo
       NISTGCR\ foo JPCRD\ foo ITL\ Bulletin\ foo CSRC\ foo].each do |ref|
      it "matches #{ref.inspect}" do
        expect(processor.defaultprefix).to match(ref)
      end
    end

    %w[ISO\ 123 RFC\ 1234].each do |ref|
      it "does not match #{ref.inspect}" do
        expect(processor.defaultprefix).not_to match(ref)
      end
    end
  end

  describe "#get" do
    it "delegates to Bibliography.get" do
      expect(Relaton::Nist::Bibliography).to receive(:get)
        .with("NIST SP 800-53", "2020", {}).and_return(:item)
      expect(processor.get("NIST SP 800-53", "2020", {})).to be :item
    end
  end

  # pubid reads some dated CSWP translation ids lossily ("04162018ar" ->
  # "04162018a"), so Db must hand get the reference as written (relaton#406).
  describe "#cache_pubid" do
    it "gives no pubid for a CSWP table id that pubid does not render back" do
      expect(processor.cache_pubid("NIST CSWP 04162018ar")).to be_nil
      expect(processor.cache_pubid("NIST CSWP 02122014pl")).to be_nil
    end

    it "gives no pubid for a translation that pubid renders in another spelling" do
      expect(processor.cache_pubid("NIST CSWP 6 spa")).to be_nil
    end

    # The answer is the numbered record with the dated id added; cached, it
    # would land on the numbered id's row.
    it "gives no pubid for a legacy dated id, so Db does not cache it" do
      expect(processor.cache_pubid("NIST CSWP 01142020")).to be_nil
    end

    it "keeps the parse of a translation that renders back" do
      expect(processor.cache_pubid("NIST.CSWP.6.spa").to_s).to eq "NIST.CSWP.6.spa"
    end

    it "keeps the parse of any other reference" do
      expect(processor.cache_pubid("NIST SP 800-53r5").to_s).to eq "NIST SP 800-53r5"
    end
  end

  describe "#fetch_data" do
    it "delegates to DataFetcher.fetch" do
      expect(Relaton::Nist::DataFetcher).to receive(:fetch)
        .with(output: "dir", format: "xml").and_return(:result)
      expect(processor.fetch_data("nist-tech-pubs", output: "dir", format: "xml")).to be :result
    end
  end

  describe "#from_xml" do
    it "delegates to Item.from_xml" do
      expect(Relaton::Nist::Item).to receive(:from_xml).with(:xml).and_return(:item)
      expect(processor.from_xml(:xml)).to be :item
    end
  end

  describe "#from_yaml" do
    it "delegates to Item.from_yaml" do
      expect(Relaton::Nist::Item).to receive(:from_yaml).with(:yaml).and_return(:item)
      expect(processor.from_yaml(:yaml)).to be :item
    end
  end

  describe "#grammar_hash" do
    it "delegates to Nist.grammar_hash" do
      expect(Relaton::Nist).to receive(:grammar_hash).once.and_return("hash123")
      expect(processor.grammar_hash).to eq "hash123"
    end

    it "memoizes the result" do
      expect(Relaton::Nist).to receive(:grammar_hash).once.and_return("hash123")
      2.times { expect(processor.grammar_hash).to eq "hash123" }
    end
  end

  describe "#remove_index_file" do
    it "removes the index file" do
      index = double("index")
      expect(Relaton::Index).to receive(:find_or_create)
        .with(:nist, url: true, file: "index-v2.yaml")
        .and_return(index)
      expect(index).to receive(:remove_file)
      processor.remove_index_file
    end
  end
end
