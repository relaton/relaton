RSpec.describe Relaton::Plateau::HitCollection do
  let(:index) { double("Index") }

  before do
    expect(Relaton::Index).to receive(:find_or_create).with(
      :plateau,
      url: "#{described_class::ENDPOINT}index-v1.zip",
      file: "index-v1.yaml"
    ).and_return(index)
  end

  describe "#find" do
    it "finds exact match" do
      expect(index).to receive(:search).and_yield(
        { id: "PLATEAU Handbook #01 2.0", file: "data/plateau-handbook-01-20.yaml" }
      ).and_return([{ id: "PLATEAU Handbook #01 2.0", file: "data/plateau-handbook-01-20.yaml" }])

      collection = described_class.new("PLATEAU Handbook #01 2.0").find
      expect(collection).to be_instance_of described_class
      expect(collection.size).to eq 1
      expect(collection.first).to be_instance_of Relaton::Plateau::Hit
    end

    it "finds all editions" do
      rows = [
        { id: "PLATEAU Handbook #01 2.0", file: "data/plateau-handbook-01-20.yaml" },
        { id: "PLATEAU Handbook #01 1.0", file: "data/plateau-handbook-01-10.yaml" },
      ]
      expect(index).to receive(:search).and_return(rows)

      collection = described_class.new("PLATEAU Handbook #01").find
      expect(collection.size).to eq 2
    end

    it "returns empty when no match" do
      expect(index).to receive(:search).and_return([])

      collection = described_class.new("PLATEAU Handbook #99 1.0").find
      expect(collection.size).to eq 0
    end
  end

  describe "#fetch_doc" do
    it "returns nil when empty" do
      expect(index).to receive(:search).and_return([])

      result = described_class.new("PLATEAU Handbook #99 1.0").find.fetch_doc
      expect(result).to be_nil
    end

    it "returns item for single edition" do
      row = { id: "PLATEAU Handbook #01 2.0", file: "data/plateau-handbook-01-20.yaml" }
      expect(index).to receive(:search).and_return([row])

      yaml = File.read "fixtures/item.yaml", encoding: "UTF-8"
      response = double(Net::HTTPResponse, body: yaml)
      expect(Net::HTTP).to receive(:get_response).and_return(response)

      result = described_class.new("PLATEAU Handbook #01 2.0").find.fetch_doc
      expect(result.docidentifier.first.content).to eq "PLATEAU Handbook #00 1.0"
    end

    it "returns item with hasEdition relations for all editions" do
      rows = [
        { id: "PLATEAU Handbook #00 2.0", file: "data/plateau-handbook-00-20.yaml" },
        { id: "PLATEAU Handbook #00 1.0", file: "data/plateau-handbook-00-10.yaml" },
      ]
      expect(index).to receive(:search).and_return(rows)

      yaml = File.read "fixtures/item.yaml", encoding: "UTF-8"
      response = double(Net::HTTPResponse, body: yaml)
      expect(Net::HTTP).to receive(:get_response).twice.and_return(response)

      result = described_class.new("PLATEAU Handbook #00").find.fetch_doc
      expect(result).to be_instance_of Relaton::Plateau::ItemData
      expect(result.relation.size).to eq 2
      expect(result.relation.first.type).to eq "hasEdition"
      expect(result.docidentifier.first.content).to eq "PLATEAU Handbook #00"
    end

    it "returns single item when all editions has only one result" do
      row = { id: "PLATEAU Handbook #00 1.0", file: "data/plateau-handbook-00-10.yaml" }
      expect(index).to receive(:search).and_return([row])

      yaml = File.read "fixtures/item.yaml", encoding: "UTF-8"
      response = double(Net::HTTPResponse, body: yaml)
      expect(Net::HTTP).to receive(:get_response).and_return(response)

      result = described_class.new("PLATEAU Handbook #00").find.fetch_doc
      expect(result.docidentifier.first.content).to eq "PLATEAU Handbook #00 1.0"
    end
  end

  describe "#index" do
    it "creates index with correct parameters" do
      collection = described_class.new("PLATEAU Handbook #01 1.0")
      expect(collection.index).to eq index
    end
  end
end
