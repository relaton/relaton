# frozen_string_literal: true

RSpec.describe Relaton::Oasis::Bibliography do
  it "raise RequestError" do
    expect(Relaton::Index).to receive(:find_or_create).and_raise SocketError
    expect do
      described_class.search "ref"
    end.to raise_error Relaton::RequestError
  end

  describe "#find_index_entry" do
    it "returns the best match row" do
      index = double("index")
      expect(Relaton::Index).to receive(:find_or_create)
        .with(:oasis, url: anything).and_return(index)
      expect(index).to receive(:search).with("amqp-core")
        .and_return([{ id: "OASISamqpcore", file: "data/amqp-core.yaml" },
                     { id: "OASISamqpcoreZ", file: "data/amqp-core-z.yaml" }])

      result = described_class.send(:find_index_entry, "amqp-core")
      expect(result).to eq(id: "OASISamqpcore", file: "data/amqp-core.yaml")
    end

    it "returns nil when no match" do
      index = double("index")
      expect(Relaton::Index).to receive(:find_or_create)
        .with(:oasis, url: anything).and_return(index)
      expect(index).to receive(:search).with("nonexistent").and_return([])

      result = described_class.send(:find_index_entry, "nonexistent")
      expect(result).to be_nil
    end
  end

  describe "#fetch_yaml" do
    let(:uri) { URI("https://example.com/data.yaml") }

    it "returns body on 200 response" do
      resp = double("response", code: "200", body: "yaml content")
      expect(Net::HTTP).to receive(:get_response).with(uri).and_return(resp)

      result = described_class.send(:fetch_yaml, uri)
      expect(result).to eq "yaml content"
    end

    it "raises RequestError on non-200 response" do
      resp = double("response", code: "404")
      expect(Net::HTTP).to receive(:get_response).with(uri).and_return(resp)

      expect do
        described_class.send(:fetch_yaml, uri)
      end.to raise_error(Relaton::RequestError, /HTTP 404/)
    end
  end

  describe "#parse_item" do
    let(:yaml) { File.read("fixtures/item.yaml") }

    it "returns ItemData with fetched date set" do
      expect do
        item = described_class.send(:parse_item, yaml, "OASIS amqp-core")
        expect(item).to be_instance_of Relaton::Oasis::ItemData
        expect(item.fetched.to_s).to eq Date.today.to_s
      end.to output(/Found/).to_stderr_from_any_process
    end

    it "logs found message" do
      expect do
        described_class.send(:parse_item, yaml, "OASIS amqp-core")
      end.to output(
        include("Found: `OASIS amqp-core`"),
      ).to_stderr_from_any_process
    end
  end

  describe "#search" do
    it "returns nil and logs 'Not found.' when no index match" do
      expect(described_class).to receive(:find_index_entry).and_return(nil)

      expect do
        result = described_class.search("OASIS nonexistent")
        expect(result).to be_nil
      end.to output(/Not found\./).to_stderr_from_any_process
    end

    it "returns ItemData when index match exists and HTTP succeeds" do
      row = { id: "OASISamqpcore", file: "data/amqp-core.yaml" }
      yaml = File.read("fixtures/item.yaml")
      expect(described_class).to receive(:find_index_entry).and_return(row)
      expect(described_class).to receive(:fetch_yaml).and_return(yaml)

      expect do
        item = described_class.search("OASIS amqp-core")
        expect(item).to be_instance_of Relaton::Oasis::ItemData
        expect(item.fetched.to_s).to eq Date.today.to_s
      end.to output(/Found/).to_stderr_from_any_process
    end
  end
end
