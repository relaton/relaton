# frozen_string_literal: true

# The api.relaton.org resolver tier (relaton#535): with `use_api`, a cache
# miss asks `GET /v3/documents/{key}` first, and the flavor's own `get` is
# the fallback for every answer the API cannot give with certainty.
RSpec.describe Relaton::Db::ApiResolver do
  include WebMock::API

  let(:db) { Relaton::Db.new "testcache", nil }
  let(:api) { "https://api.relaton.org/v3/documents" }

  def item(klass, id, type)
    docid = Relaton::Bib::Docidentifier.new(content: id, type: type,
                                            primary: true)
    klass.new(docidentifier: [docid], fetched: Date.today.to_s)
  end

  def iso_item(id) = item(Relaton::Iso::ItemData, id, "ISO")

  def stub_api(path, status: 200, body: "")
    stub_request(:get, "#{api}/#{path}")
      .with(headers: { "Accept" => "application/yaml" })
      .to_return(status: status, body: body,
                 headers: { "Content-Type" => "application/yaml" })
  end

  def rows(dir)
    Relaton::Db::Cache.new(dir).rows.map do |r|
      r.to_h.except("fetched", :fetched)
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
