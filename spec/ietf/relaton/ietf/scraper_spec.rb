RSpec.describe Relaton::Ietf::Scraper do
  context "raise network error" do
    it "Timeout::Error" do
      expect(described_class).to receive(:fetch_doc).and_raise Timeout::Error
      expect do
        described_class.scrape_page "RFC 1"
      end.to raise_error Relaton::RequestError
    end

    it "SocketError" do
      expect(described_class).to receive(:fetch_doc).and_raise SocketError
      expect do
        described_class.scrape_page "RFC 1"
      end.to raise_error Relaton::RequestError
    end
  end

  # One index for every stream, from the combined relaton-data-ietf repo — not
  # the three per-type indexes this flavor used to read.
  describe "#index" do
    it "opens the combined pubid index" do
      expect(Relaton::Index).to receive(:find_or_create).with(
        :IETF,
        url: "#{described_class::IETF}index-v2.zip",
        file: "index-v2.yaml",
        pubid_class: ::Pubid::Ietf::Identifier
      )
      described_class.send :index
    end
  end

  # The whole point of the migration. `Type#search_candidates` narrows only for
  # non-String queries, and a String query against a pubid index renders every
  # id in it — ~40 s per lookup over 177k rows. So the reference has to reach
  # `search` already parsed.
  describe "#parse_id" do
    {
      "RFC 8341" => "RFC 8341",
      "BCP 47" => "BCP 47",
      "FYI 2" => "FYI 2",
      "STD 3" => "STD 3",
      "draft-abarth-cake-01" => "draft-abarth-cake-01",
      # The I-D prefix is stripped, in both its "." and " " spellings.
      "I-D.draft-abarth-cake-01" => "draft-abarth-cake-01",
      "I-D draft-abarth-cake-01" => "draft-abarth-cake-01",
      # `I-D.foo` without the `draft-` stem is the bibxml anchor spelling, and
      # the docnumber IETF records themselves carry. The old string index
      # matched it by substring; keep it resolving now that matching is exact.
      "I-D.ietf-quic-transport" => "draft-ietf-quic-transport",
    }.each do |ref, rendered|
      it "parses #{ref}" do
        expect(described_class.send(:parse_id, ref).to_s).to eq rendered
      end
    end

    # `Bibliography.get "CN 8341"` must log "Not found." rather than blow up on
    # a reference pubid has no grammar for.
    it "returns nil for a reference pubid cannot parse" do
      expect(described_class.send(:parse_id, "CN 8341")).to be_nil
    end
  end

  describe "#scrape_page" do
    it "searches the index with a parsed identifier, never a String" do
      index = double("index")
      allow(described_class).to receive(:index).and_return index
      expect(index).to receive(:search) do |arg|
        expect(arg).to be_a ::Pubid::Ietf::Identifier
        expect(arg.to_s).to eq "RFC 8341"
        [{ id: arg, file: "data/RFC8341.yaml" }]
      end
      expect(described_class).to receive(:get_page)
        .with("#{described_class::IETF}data/RFC8341.yaml")

      described_class.scrape_page "IETF RFC 8341"
    end

    it "returns nil when the reference does not parse" do
      expect(described_class).not_to receive(:get_page)
      expect(described_class.scrape_page("CN 8341")).to be_nil
    end

    it "returns nil when the index has no such row" do
      index = double("index")
      allow(described_class).to receive(:index).and_return index
      expect(index).to receive(:search).and_return []
      expect(described_class).not_to receive(:get_page)

      expect(described_class.scrape_page("RFC 0")).to be_nil
    end
  end
end
