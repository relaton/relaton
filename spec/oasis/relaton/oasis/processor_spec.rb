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
    expect(processor.instance_variable_get(:@pubid_flavor)).to eq :Oasis
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
    # `url: true` names the cached file. No `pubid_class:`: Type#remove_file
    # deletes the file and never reads the index.
    it "calls remove_file on the index" do
      index = double("index")
      expect(Relaton::Index).to receive(:find_or_create)
        .with(:oasis, url: true, file: "index-v2.yaml")
        .and_return(index)
      expect(index).to receive(:remove_file)
      processor.remove_index_file
    end

    # Db#clear reaches this with an empty pool. Without `url: true` the file
    # is the bare name, so the delete hit ./index-v2.yaml in the working
    # directory and left the cache in place.
    context "when the index pool is empty" do
      let(:dir) { Dir.mktmpdir }
      let(:cached) do
        File.join(dir, "home", ".relaton", "oasis", "index-v2.yaml")
      end

      # A `before`, not an `around`: support/webmock.rb seeds the pool with
      # the fixture index in a global `before`, and an `around` runs ahead of
      # it. The fixture must not be the entry that is removed.
      before do
        @storage_dir = Relaton::Index.config.storage_dir
        Relaton::Index.configure { |c| c.storage_dir = File.join(dir, "home") }
        Relaton::Index.close(:oasis)
      end

      after do
        Relaton::Index.configure { |c| c.storage_dir = @storage_dir }
        FileUtils.rm_rf dir
      end

      it "removes the cached index and keeps a local index-v2.yaml" do
        FileUtils.mkdir_p File.dirname(cached)
        File.write cached, "--- []\n"
        Dir.chdir(dir) do
          File.write "index-v2.yaml", "--- []\n"
          processor.remove_index_file
          expect(File.exist?("index-v2.yaml")).to be true
        end
        expect(File.exist?(cached)).to be false
      end
    end
  end
end
