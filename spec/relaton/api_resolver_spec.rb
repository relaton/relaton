# frozen_string_literal: true

# The api.relaton.org resolver tier (relaton#535): with `use_api`, a cache
# miss asks `GET /v3/documents/{key}` first, and the flavor's own `get` is
# the fallback for every answer the API cannot give with certainty.
RSpec.describe Relaton::Db::ApiResolver do
  include WebMock::API

  let(:db) { Relaton::Db.new "testcache", nil }
  let(:api) { "https://api.relaton.org/v3/documents" }

  def item(klass, id, type, fetched: Date.today)
    docid = Relaton::Bib::Docidentifier.new(content: id, type: type,
                                            primary: true)
    klass.new(docidentifier: [docid], fetched: fetched.to_s)
  end

  def iso_item(id, **) = item(Relaton::Iso::ItemData, id, "ISO", **)

  def stub_api(path, status: 200, body: "")
    stub_request(:get, "#{api}/#{path}")
      .with(headers: { "Accept" => "application/yaml" })
      .to_return(status: status, body: body,
                 headers: { "Content-Type" => "application/yaml" })
  end

  # An API row also holds the answer's ETag; the rest is a flavor row.
  def rows(dir)
    Relaton::Db::Cache.new(dir).rows.map do |r|
      r.to_h.except("fetched", "etag")
    end
  end

  before do
    FileUtils.rm_rf %w[testcache testcache2]
    Relaton::Db.configure { |c| c.use_api = true }
  end

  after do
    WebMock.reset!
    FileUtils.rm_rf %w[testcache testcache2]
    Relaton::Db.instance_variable_set :@configuration, nil
    Relaton::Db.configure { |c| c.use_api = false }
  end

  context "a dated reference the API holds" do
    let!(:request) do
      stub_api "ISO%2019115-1%3A2014",
               body: iso_item("ISO 19115-1:2014").to_yaml
    end

    it "answers from the API, not from the flavor" do
      expect(Relaton::Iso::Bibliography).not_to receive(:get)
      bib = db.fetch "ISO 19115-1:2014"
      expect(bib).to be_instance_of Relaton::Iso::ItemData
      expect(bib.docidentifier.first.content).to eq "ISO 19115-1:2014"
      assert_requested request, times: 1
    end

    it "answers the second fetch from the cache" do
      2.times { db.fetch "ISO 19115-1:2014" }
      assert_requested request, times: 1
    end

    it "writes the rows and the document of a flavor fetch" do
      db.fetch "ISO 19115-1:2014"
      Relaton::Db.configure { |c| c.use_api = false }
      allow(Relaton::Iso::Bibliography).to receive(:get)
        .and_return iso_item("ISO 19115-1:2014")
      Relaton::Db.new("testcache2", nil).fetch "ISO 19115-1:2014"
      expect(rows("testcache")).to eq rows("testcache2")
      expect(Relaton::Db::Cache.new("testcache").all)
        .to eq Relaton::Db::Cache.new("testcache2").all
    end
  end

  it "sends the flavor's canonical form of the reference" do
    request = stub_api(
      "RFC%208341",
      body: item(Relaton::Ietf::ItemData, "RFC 8341", "IETF").to_yaml,
    )
    expect(Relaton::Ietf::Bibliography).not_to receive(:get)
    bib = db.fetch "IETF RFC 8341"
    expect(bib.docidentifier.first.content).to eq "RFC 8341"
    assert_requested request, times: 1
  end

  context "falls back to the flavor" do
    before do
      allow(Relaton::Iso::Bibliography).to receive(:get)
        .and_return iso_item("ISO 19115-1:2014")
    end

    def expect_flavor_answer(ref = "ISO 19115-1:2014")
      bib = db.fetch ref
      assert_requested :get, /api\.relaton\.org/, times: 1
      expect(Relaton::Iso::Bibliography).to have_received(:get)
      expect(bib.docidentifier.first.content).to eq "ISO 19115-1:2014"
    end

    it "when the API does not hold the reference" do
      stub_api "ISO%2019115-1%3A2014", status: 404,
                                       body: '{"status":404}'
      expect_flavor_answer
    end

    it "when the API fails" do
      stub_api "ISO%2019115-1%3A2014", status: 500
      expect_flavor_answer
    end

    it "when the API times out" do
      stub_request(:get, "#{api}/ISO%2019115-1%3A2014").to_timeout
      expect_flavor_answer
    end

    it "when the API answers a body the flavor cannot read" do
      stub_api "ISO%2019115-1%3A2014", body: "- [unclosed"
      expect_flavor_answer
    end

    it "when the API answers another document than the reference names" do
      # The API has no undated logic: `ISO 19115-1` answers the 2014 record.
      stub_api "ISO%2019115-1", body: iso_item("ISO 19115-1:2014").to_yaml
      expect_flavor_answer "ISO 19115-1"
    end

    it "when the API answers YAML that is not a document" do
      stub_api "ISO%2019115-1%3A2014", body: "--- []\n"
      expect_flavor_answer
    end

    it "without a request for a publication date range" do
      db.fetch "ISO 19115-1:2014", nil, publication_date_before: "2015"
      expect(Relaton::Iso::Bibliography).to have_received(:get)
      assert_not_requested :get, /api\.relaton\.org/
    end

    it "without a request for an all-parts reference" do
      db.fetch "ISO 19115", nil, all_parts: true
      expect(Relaton::Iso::Bibliography).to have_received(:get)
      assert_not_requested :get, /api\.relaton\.org/
    end
  end

  it "escapes a slash in the reference as part of one path segment" do
    request = stub_api(
      "ISO%2FIEC%2027001%3A2022",
      body: iso_item("ISO/IEC 27001:2022").to_yaml,
    )
    db.fetch "ISO/IEC 27001:2022"
    assert_requested request, times: 1
  end

  it "joins an api_host that ends with a slash" do
    Relaton::Db.configure { |c| c.api_host = "https://api.relaton.org/" }
    request = stub_api "ISO%2019115-1%3A2014",
                       body: iso_item("ISO 19115-1:2014").to_yaml
    db.fetch "ISO 19115-1:2014"
    assert_requested request, times: 1
  end

  # The local store is the API tier's cache (relaton#536): what an online
  # fetch through the API writes is what offline resolution reads.
  context "the local store as the API tier's cache" do
    let(:ref) { "ISO 19115-1:2014" }
    let(:path) { "ISO%2019115-1%3A2014" }
    let(:stale) { iso_item(ref, fetched: Date.today - 61) }

    def docid(bib) = bib.docidentifier.first.content

    def fetched_dates
      Relaton::Db::Cache.new("testcache").rows.map { _1["fetched"] }.uniq
    end

    # Seed the cache, with the API off, with a flavor answer whose rows
    # are 61 days old. Each example then stubs `get` again.
    def seed_stale
      Relaton::Db.configuration.use_api = false
      allow(Relaton::Iso::Bibliography).to receive(:get).and_return stale
      db.fetch ref
      Relaton::Db.configuration.use_api = true
    end

    it "populates what offline resolution consumes" do
      request = stub_api path, body: iso_item(ref).to_yaml
      db.fetch ref
      Relaton::Db.configure { |c| c.offline = true }
      expect(Relaton::Iso::Bibliography).not_to receive(:get)
      expect(docid(Relaton::Db.new("testcache", nil).fetch(ref))).to eq ref
      assert_requested request, times: 1
    end

    it "serves a stale row when the API and the flavor both fail" do
      seed_stale
      request = stub_api path, status: 500
      allow(Relaton::Iso::Bibliography).to receive(:get)
        .and_raise Relaton::RequestError, "no network"
      expect { expect(docid(db.fetch(ref))).to eq ref }
        .to output(/WARN.*cached entry fetched #{Date.today - 61}/)
        .to_stderr_from_any_process
      expect(fetched_dates).to eq [(Date.today - 61).to_s]
      assert_requested request, times: 1
    end

    it "replaces a stale row with the API answer" do
      seed_stale
      request = stub_api path, body: iso_item(ref).to_yaml
      expect(Relaton::Iso::Bibliography).not_to receive(:get)
      expect(docid(db.fetch(ref))).to eq ref
      expect(fetched_dates).to eq [Date.today.to_s]
      assert_requested request, times: 1
    end
  end

  # A stale row the API wrote revalidates with its ETag: a 304 keeps the
  # cached document for another TTL, with no body and no flavor call.
  context "ETag revalidation" do
    let(:ref) { "ISO 19115-1:2014" }
    let(:url) { "#{api}/ISO%2019115-1%3A2014" }
    let(:etag) { '"v1"' }

    def docid(bib) = bib.docidentifier.first.content

    def cache = Relaton::Db::Cache.new("testcache")

    def fetched_dates = cache.rows.map { _1["fetched"] }.uniq

    def etags = cache.rows.map { _1["etag"] }.uniq

    def answer(status: 200, body: "", etag: nil)
      headers = { "Content-Type" => "application/yaml" }
      headers["ETag"] = etag if etag
      { status: status, body: body, headers: headers }
    end

    # An API answer 61 days old, with its ETag.
    def seed_api_stale
      stub_request(:get, url).to_return(
        answer(body: iso_item(ref, fetched: Date.today - 61).to_yaml,
               etag: etag),
      )
      db.fetch ref
      WebMock.reset!
    end

    def conditional
      stub_request(:get, url)
        .with(headers: { "Accept" => "application/yaml",
                         "If-None-Match" => etag })
    end

    it "keeps the ETag of an API answer" do
      stub_request(:get, url).to_return(
        answer(body: iso_item(ref).to_yaml, etag: etag),
      )
      db.fetch ref
      expect(etags).to eq [etag]
    end

    it "keeps no ETag for a flavor answer" do
      stub_request(:get, url).to_return(answer(status: 404))
      allow(Relaton::Iso::Bibliography).to receive(:get)
        .and_return iso_item(ref)
      db.fetch ref
      expect(etags).to eq [nil]
    end

    it "keeps the cached document on a 304" do
      seed_api_stale
      request = conditional.to_return(answer(status: 304, etag: etag))
      expect(Relaton::Iso::Bibliography).not_to receive(:get)
      expect(docid(db.fetch(ref))).to eq ref
      expect(fetched_dates).to eq [Date.today.to_s]
      expect(etags).to eq [etag]
      assert_requested request, times: 1
      # valid again: the next fetch makes no request
      db.fetch ref
      assert_requested :get, url, times: 1
    end

    it "replaces the document and the ETag on a 200" do
      seed_api_stale
      request = conditional.to_return(
        answer(body: iso_item(ref).to_yaml, etag: '"v2"'),
      )
      expect(Relaton::Iso::Bibliography).not_to receive(:get)
      db.fetch ref
      expect(fetched_dates).to eq [Date.today.to_s]
      expect(etags).to eq ['"v2"']
      assert_requested request, times: 1
    end

    it "asks the flavor when the revalidation fails" do
      seed_api_stale
      request = conditional.to_return(answer(status: 500))
      allow(Relaton::Iso::Bibliography).to receive(:get)
        .and_return iso_item(ref)
      db.fetch ref
      expect(Relaton::Iso::Bibliography).to have_received(:get)
      expect(fetched_dates).to eq [Date.today.to_s]
      expect(etags).to eq [nil]
      assert_requested request, times: 1
    end

    it "keeps no ETag when the revalidation answers another document" do
      seed_api_stale
      request = conditional.to_return(
        answer(body: iso_item("ISO 19115-1:2003").to_yaml, etag: '"v2"'),
      )
      allow(Relaton::Iso::Bibliography).to receive(:get)
        .and_return iso_item(ref)
      db.fetch ref
      expect(Relaton::Iso::Bibliography).to have_received(:get)
      expect(etags).to eq [nil]
      assert_requested request, times: 1
    end

    it "asks the flavor when the stale document does not read back" do
      seed_api_stale
      conditional.to_return(answer(status: 304, etag: etag))
      # The first read is the stale document's; later reads are the
      # flavor answer's, as Db returns it.
      calls = 0
      processor = Relaton::Db::Registry.instance[:relaton_iso]
      allow(processor).to receive(:from_xml).and_wrap_original do |m, xml|
        calls += 1
        raise ArgumentError, "bad xml" if calls == 1

        m.call(xml)
      end
      allow(Relaton::Iso::Bibliography).to receive(:get)
        .and_return iso_item(ref)
      db.fetch ref
      expect(Relaton::Iso::Bibliography).to have_received(:get)
      expect(etags).to eq [nil]
    end

    it "sends no If-None-Match with no_cache" do
      seed_api_stale
      request = stub_request(:get, url).to_return(
        answer(body: iso_item(ref).to_yaml, etag: '"v2"'),
      )
      db.fetch ref, nil, no_cache: true
      assert_requested(:get, url, times: 1) do |req|
        !req.headers.key?("If-None-Match")
      end
      assert_requested request, times: 1
    end

    it "sends no If-None-Match for a stale row with no ETag" do
      Relaton::Db.configuration.use_api = false
      allow(Relaton::Iso::Bibliography).to receive(:get)
        .and_return iso_item(ref, fetched: Date.today - 61)
      db.fetch ref
      Relaton::Db.configuration.use_api = true
      request = stub_request(:get, url).to_return(
        answer(body: iso_item(ref).to_yaml, etag: etag),
      )
      db.fetch ref
      assert_requested(:get, url, times: 1) do |req|
        !req.headers.key?("If-None-Match")
      end
      assert_requested request, times: 1
      expect(etags).to eq [etag]
    end
  end

  it "makes no request in offline mode" do
    Relaton::Db.configure { |c| c.offline = true }
    expect { db.fetch "ISO 19115-1:2014" }
      .to raise_error Relaton::NotInLocalStoreError
    assert_not_requested :get, /api\.relaton\.org/
  end

  it "makes no request when use_api is off" do
    Relaton::Db.configure { |c| c.use_api = false }
    allow(Relaton::Iso::Bibliography).to receive(:get)
      .and_return iso_item("ISO 19115-1:2014")
    db.fetch "ISO 19115-1:2014"
    assert_not_requested :get, /api\.relaton\.org/
  end
end
