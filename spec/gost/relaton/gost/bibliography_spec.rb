RSpec.describe Relaton::Gost::Bibliography do
  let(:endpoint) { described_class::ENDPOINT }

  # A minimal GOST record, serialized the way the relaton-data-gost repo
  # stores it, so the stubbed HTTP body round-trips through Item.from_yaml.
  let(:item_yaml) do
    Relaton::Gost::Item.from_hash(
      "id" => "GOST R 34.12-2015",
      "type" => "standard",
      "docidentifier" => [{
        "content" => "GOST R 34.12-2015", "type" => "GOST", "primary" => true
      }],
      "ext" => { "doctype" => { "content" => "national" },
                 "flavor" => "gost",
                 "urn" => "urn:gost:std:r:34.12:2015" },
    ).to_yaml
  end

  def stub_index(rows)
    index = double "index"
    allow(index).to receive(:search).and_return rows
    allow(Relaton::Index).to receive(:find_or_create).with(
      :gost,
      url: "#{endpoint}#{Relaton::Gost::INDEXFILE}.zip",
      file: "#{Relaton::Gost::INDEXFILE}.yaml",
    ).and_return index
    index
  end

  context "when the code is in the index" do
    before do
      stub_index([{ id: "GOST R 34.12-2015", file: "data/gost-r-34.12-2015.yaml" }])
      stub_request(:get, "#{endpoint}data/gost-r-34.12-2015.yaml")
        .to_return(status: 200, body: item_yaml)
    end

    it "returns a populated Relaton::Gost::ItemData" do
      result = described_class.get "GOST R 34.12-2015"
      expect(result).to be_instance_of Relaton::Gost::ItemData
      expect(result.docidentifier.first.content).to eq "GOST R 34.12-2015"
      expect(result.ext.urn).to eq "urn:gost:std:r:34.12:2015"
    end

    it "stamps the fetched date" do
      result = described_class.get "GOST R 34.12-2015"
      expect(result.fetched).to eq Date.today.to_s
    end

    it "routes a Cyrillic reference through the same path" do
      # The index search is stubbed to match regardless of surface form, so a
      # Cyrillic citation resolves to the same record.
      result = described_class.get "ГОСТ Р 34.12-2015"
      expect(result).to be_instance_of Relaton::Gost::ItemData
    end
  end

  context "when the code is not in the index" do
    before { stub_index([]) }

    it "returns nil" do
      expect(described_class.get("GOST 9999-99")).to be_nil
    end
  end

  context "when the data repo returns a non-200" do
    before do
      stub_index([{ id: "GOST R 34.12-2015", file: "data/gost-r-34.12-2015.yaml" }])
      stub_request(:get, "#{endpoint}data/gost-r-34.12-2015.yaml")
        .to_return(status: 404, body: "")
    end

    it "raises Relaton::RequestError" do
      expect { described_class.get "GOST R 34.12-2015" }
        .to raise_error Relaton::RequestError
    end
  end
end
