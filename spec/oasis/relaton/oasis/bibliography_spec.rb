# frozen_string_literal: true

RSpec.describe Relaton::Oasis::Bibliography do
  it "raise RequestError" do
    expect(Relaton::Index).to receive(:find_or_create).and_raise SocketError
    expect do
      described_class.search "ref"
    end.to raise_error Relaton::RequestError
  end

  # Runs against the seeded index-v2 fixture (605 published rows), not doubles:
  # what is being tested is the narrowing and the ordering, and a double would
  # only restate the code.
  describe "#find_index_entry" do
    def match(ref)
      described_class.send(:find_index_entry, ref)&.dig(:file)
    end

    it "resolves an exact reference to its own row" do
      expect(match("OASIS amqp-core-types-v1.0-Pt1"))
        .to eq "data/oasis-amqp-core-types-v1-0-pt1.yaml"
    end

    it "accepts a reference without the OASIS token" do
      expect(match("amqp-core-types-v1.0-Pt1"))
        .to eq "data/oasis-amqp-core-types-v1-0-pt1.yaml"
    end

    it "accepts the OASIS token in any case" do
      expect(match("oasis amqp-core")).to eq "data/oasis-amqp-core.yaml"
      expect(match("Oasis amqp-core")).to eq "data/oasis-amqp-core.yaml"
    end

    # The token is case-insensitive; the slug after it is not.
    it "keeps the slug case-sensitive" do
      expect(match("OASIS stix")).to be_nil
    end

    it "resolves a spec that has exactly one row" do
      expect(match("OASIS amqp-core")).to eq "data/oasis-amqp-core.yaml"
    end

    # EDXL, OData, OSLC, SAML and WSS each exist as a bare record AND as
    # versioned siblings. Without the exact-match rule, three of them answered
    # with the newest sibling instead of themselves.
    it "prefers a record whose printed id is exactly the reference" do
      expect(match("OASIS EDXL")).to eq "data/oasis-edxl.yaml"
      expect(match("OASIS SAML")).to eq "data/oasis-saml.yaml"
      expect(match("OASIS WSS")).to eq "data/oasis-wss.yaml"
    end

    it "gives a bare spec name its newest, least qualified record" do
      # 25 STIX rows: v1.2.1 and v2.0 parts, v2.1-CS01, v2.1-CS02, v2.1.
      expect(match("OASIS STIX")).to eq "data/oasis-stix-v2-1.yaml"
    end

    it "prefers the record itself over its labelled parts" do
      expect(match("OASIS STIX-v1.2.1-CS01"))
        .to eq "data/oasis-stix-v1-2-1-cs01.yaml"
    end

    it "honours an explicit stage revision" do
      expect(match("OASIS STIX-v2.1-CS01"))
        .to eq "data/oasis-stix-v2-1-cs01.yaml"
    end

    it "compares version segments as integers, not text" do
      # "v1.2.1" must not beat "v2.1" the way a string compare would.
      id = described_class.send(:find_index_entry, "OASIS STIX")[:id]
      expect(id.version).to eq "v2.1"
    end

    it "returns nil when nothing matches" do
      expect(match("OASIS no-such-specification")).to be_nil
    end

    it "returns nil, and warns, when pubid cannot parse the reference" do
      # Util.warn reaches the logger through method_missing, so the
      # expectation goes on the pool rather than on Util.
      expect(Relaton.logger_pool).to receive(:warn)
        .with(/Failed to parse pubid/, any_args)
      expect(match("")).to be_nil
    end

    # v1 matched by substring, so a partial name resolved to some record;
    # v2 matches identifiers. This is the IANA semantic change, asserted so it
    # is a decision and not a surprise.
    it "no longer resolves a partial specification name" do
      expect(match("OASIS amqp")).to be_nil
    end
  end

  describe "index narrowing" do
    let(:index) { described_class.send(:index) }

    it "deserializes the rows into pubid identifiers" do
      expect(index.index).to all include(
        id: an_instance_of(Pubid::Oasis::Identifiers::Standard),
      )
    end

    it "binary-searches by number instead of scanning the whole index" do
      pubid = Pubid::Oasis::Identifier.parse "OASIS STIX"
      candidates = index.send(:candidates_by_number, pubid)
      expect(index.index.size).to be > 600
      expect(candidates.map { |r| r[:id].number }.uniq).to eq ["STIX"]
      expect(candidates.size).to eq 25
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
