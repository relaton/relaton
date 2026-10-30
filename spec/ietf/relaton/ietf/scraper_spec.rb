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

  # One machine index for every stream, read from the data repo's Pages site
  # (relaton#206, the W3C pilot's contract) — not the three per-type indexes
  # this flavor used to read, and not the zip download.
  describe "#index" do
    it "opens the machine index on the Pages site" do
      expect(Relaton::Index).to receive(:find_or_create).with(
        :IETF,
        pages_url: Relaton::Ietf::PAGES_URL,
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

    # The capture must start non-space. With `(.+)` the greedy `\s*` backtracks
    # one position when nothing else follows, capturing a lone space, which then
    # became the nonsense slug "draft- ". That overlap between `\s*` and the
    # capture is also what CodeQL's rb/polynomial-redos models.
    it "returns nil for an I-D prefix with nothing but whitespace after it" do
      ["I-D.", "I-D.   ", "I-D \t "].each do |ref|
        expect(described_class.send(:parse_id, ref)).to be_nil
      end
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

    it "searches the index with a given pubid, and leaves it as it was (relaton#205)" do
      pubid = ::Pubid::Ietf::Identifier.parse "RFC 8341"
      hash = pubid.to_hash
      index = double("index")
      allow(described_class).to receive(:index).and_return index
      expect(index).to receive(:search).with(pubid, exact: true)
        .and_return [{ id: pubid, file: "data/RFC8341.yaml" }]
      expect(described_class).to receive(:get_page)
        .with("#{described_class::IETF}data/RFC8341.yaml")

      described_class.scrape_page pubid
      expect(pubid.to_hash).to eq hash
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

  # relaton-ietf#125: the data repo crawls the rsync `bibxml-ids` snapshot,
  # which holds only some versions of each draft. bib.ietf.org serves the
  # others, so a versioned draft the index lacks is read from there.
  describe "fallback to bib.ietf.org" do
    let(:index) { double("index", search: []) }
    let(:url) do
      "#{described_class::BIBXML_IDS}reference.I-D.draft-ietf-vcarddav-vcardrev-06.xml"
    end

    before { allow(described_class).to receive(:index).and_return index }

    it "reads a versioned Internet-Draft the index lacks" do
      stub_request(:get, url).to_return(
        status: 200, body: File.binread("fixtures/reference.I-D.draft-ietf-vcarddav-vcardrev-06.xml"),
      )
      item = described_class.scrape_page "I-D draft-ietf-vcarddav-vcardrev-06"
      expect(item).to be_instance_of Relaton::Ietf::ItemData
      expect(item.docidentifier.detect(&:primary).content).to eq "draft-ietf-vcarddav-vcardrev-06"
      expect(item.version.map(&:content)).to eq ["06"]
      expect(item.fetched).to eq Date.today.to_s
    end

    it "returns nil when bib.ietf.org has no such version" do
      stub_request(:get, url).to_return(status: 404, body: "{}")
      expect(described_class.scrape_page("draft-ietf-vcarddav-vcardrev-06")).to be_nil
    end

    it "raises a RequestError on a 503, so Db retries it and caches nothing" do
      stub_request(:get, url).to_return(status: 503, body: "")
      expect do
        described_class.scrape_page "draft-ietf-vcarddav-vcardrev-06"
      end.to raise_error Relaton::RequestError, /503/
    end

    it "raises a RequestError when bib.ietf.org cannot be reached" do
      stub_request(:get, url).to_raise Errno::ECONNREFUSED
      expect do
        described_class.scrape_page "draft-ietf-vcarddav-vcardrev-06"
      end.to raise_error Relaton::RequestError
    end

    ["", "<html><body>oops</body></html>"].each do |body|
      it "returns nil for a 200 that is not bibxml (#{body.inspect})" do
        stub_request(:get, url).to_return(status: 200, body: body)
        expect do
          expect(described_class.scrape_page("draft-ietf-vcarddav-vcardrev-06")).to be_nil
        end.to output(/Unreadable bibxml for `draft-ietf-vcarddav-vcardrev-06`/).to_stderr_from_any_process
      end
    end

    it "does not ask bib.ietf.org when the index has the row" do
      allow(index).to receive(:search).and_return [{ file: "data/x.yaml" }]
      expect(described_class).to receive(:get_page).and_return :item
      expect(described_class).not_to receive(:fetch_bibxml)
      described_class.scrape_page "draft-ietf-vcarddav-vcardrev-06"
    end

    # The index has every unversioned aggregator, RFC and sub-series, so a
    # miss there is a real "not found".
    ["draft-ietf-vcarddav-vcardrev", "RFC 0", "BCP 0"].each do |ref|
      it "does not ask bib.ietf.org for #{ref}" do
        expect(described_class).not_to receive(:fetch_bibxml)
        expect(described_class.scrape_page(ref)).to be_nil
      end
    end
  end
end
