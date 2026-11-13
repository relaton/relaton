# Offline resolution from the local store (relaton#536): a stale entry is a
# refresh candidate, not garbage; a cache-only fetch never deletes what it
# reads; offline mode answers from the store or raises a clear error.
RSpec.describe Relaton::Db do
  let(:db) { described_class.new "testcache", nil }

  def iso_item(id, fetched: Date.today)
    docid = Relaton::Bib::Docidentifier.new(content: id, type: "ISO",
                                            primary: true)
    Relaton::Iso::ItemData.new(docidentifier: [docid],
                               fetched: fetched.to_s)
  end

  def docid(bib)
    bib.docidentifier.first.content
  end

  def rows(dir = "testcache")
    Relaton::Db::Cache.new(dir).rows
  end

  # Seed the cache with an undated query whose rows are 61 days old.
  def seed_stale(ref = "ISO 19115-1", id = "ISO 19115-1:2014")
    allow(Relaton::Iso::Bibliography).to receive(:get)
      .and_return iso_item(id, fetched: Date.today - 61)
    db.fetch ref
    RSpec::Mocks.space.proxy_for(Relaton::Iso::Bibliography).reset
  end

  before { FileUtils.rm_rf %w[testcache testcache2] }

  after do
    FileUtils.rm_rf %w[testcache testcache2]
    described_class.instance_variable_set :@configuration, nil
  end

  context "a stale entry" do
    before { seed_stale }

    it "answers fetch_db and keeps its rows" do
      count = rows.size
      expect(Relaton::Iso::Bibliography).not_to receive(:get)
      expect(docid(db.fetch_db("ISO 19115-1"))).to eq "ISO 19115-1:2014"
      expect(rows.size).to eq count
    end

    it "is served when the refetch fails with a transport error" do
      expect(Relaton::Iso::Bibliography).to receive(:get)
        .and_raise Relaton::RequestError, "no network"
      expect do
        expect(docid(db.fetch("ISO 19115-1"))).to eq "ISO 19115-1:2014"
      end.to output(/WARN.*cached entry fetched #{Date.today - 61}/)
        .to_stderr_from_any_process
      expect(rows.map { _1["fetched"] }.uniq).to eq [(Date.today - 61).to_s]
    end

    it "is replaced when the refetch succeeds" do
      expect(Relaton::Iso::Bibliography).to receive(:get)
        .and_return iso_item("ISO 19115-1:2014")
      expect(docid(db.fetch("ISO 19115-1"))).to eq "ISO 19115-1:2014"
      expect(rows.map { _1["fetched"] }.uniq).to eq [Date.today.to_s]
    end
  end

  it "raises for a stale not_found whose refetch fails" do
    allow(Relaton::Iso::Bibliography).to receive(:get).and_return nil
    db.fetch "ISO 9999", "2030"
    Relaton::Db::Cache.new("testcache")[
      Pubid::Iso::Identifier.parse("ISO 9999:2030")
    ] = "not_found #{Date.today - 61}"
    allow(Relaton::Iso::Bibliography).to receive(:get)
      .and_raise Relaton::RequestError, "no network"
    expect { db.fetch "ISO 9999", "2030" }
      .to raise_error Relaton::RequestError
  end

  it "writes no row for a fetch that raises" do
    expect(Relaton::Iso::Bibliography).to receive(:get)
      .and_raise Relaton::RequestError, "no network"
    expect { db.fetch "ISO 19115-1" }.to raise_error Relaton::RequestError
    expect(rows).to be_empty
  end

  it "answers fetch_db from the local cache when only it holds the row" do
    local = described_class.new nil, "testcache2"
    allow(Relaton::Iso::Bibliography).to receive(:get)
      .and_return iso_item("ISO 19115-1:2014")
    local.fetch "ISO 19115-1:2014"
    both = described_class.new "testcache", "testcache2"
    expect(Relaton::Iso::Bibliography).not_to receive(:get)
    expect(docid(both.fetch_db("ISO 19115-1:2014"))).to eq "ISO 19115-1:2014"
  end

  context "with a local and a global cache" do
    let(:both) { described_class.new "testcache", "testcache2" }

    it "answers fetch_db with the global document over a local not_found" do
      allow(Relaton::Iso::Bibliography).to receive(:get)
        .and_return iso_item("ISO 19115-1:2014")
      described_class.new("testcache", nil).fetch "ISO 19115-1"
      Relaton::Db::Cache.new("testcache2")[
        Pubid::Iso::Identifier.parse("ISO 19115-1")
      ] = "not_found #{Date.today - 61}"
      expect(docid(both.fetch_db("ISO 19115-1"))).to eq "ISO 19115-1:2014"
    end

    it "serves the global stale document when the local has no row" do
      seed_stale # the global cache, testcache
      expect(Relaton::Iso::Bibliography).to receive(:get)
        .and_raise Relaton::RequestError, "no network"
      expect do
        expect(docid(both.fetch("ISO 19115-1"))).to eq "ISO 19115-1:2014"
      end.to output(/cached entry fetched #{Date.today - 61}/)
        .to_stderr_from_any_process
    end

    it "refreshes both caches when the refetch answers" do
      seed_stale
      expect(Relaton::Iso::Bibliography).to receive(:get)
        .and_return iso_item("ISO 19115-1:2014")
      both.fetch "ISO 19115-1"
      key = Pubid::Iso::Identifier.parse("ISO 19115-1")
      %w[testcache testcache2].each do |dir|
        expect(Relaton::Db::Cache.new(dir).fetched(key))
          .to eq Date.today.to_s
      end
    end
  end

  it "has no stale fallback under no_cache" do
    seed_stale
    expect(Relaton::Iso::Bibliography).to receive(:get)
      .and_raise Relaton::RequestError, "no network"
    expect { db.fetch "ISO 19115-1", nil, no_cache: true }
      .to raise_error Relaton::RequestError
    expect(docid(db.fetch_db("ISO 19115-1"))).to eq "ISO 19115-1:2014"
  end

  context "offline mode" do
    before { described_class.configure { |c| c.offline = true } }

    it "answers a stored document with no call to the flavor" do
      described_class.configuration.offline = false
      seed_stale
      described_class.configuration.offline = true
      expect(Relaton::Iso::Bibliography).not_to receive(:get)
      expect(docid(db.fetch("ISO 19115-1"))).to eq "ISO 19115-1:2014"
    end

    it "raises NotInLocalStoreError for a reference the store lacks" do
      expect(Relaton::Iso::Bibliography).not_to receive(:get)
      expect { db.fetch "ISO 19115-1" }
        .to raise_error(Relaton::NotInLocalStoreError, /ISO 19115-1/)
      expect(Relaton::NotInLocalStoreError.ancestors)
        .to include Relaton::Error
      expect(Relaton::NotInLocalStoreError.ancestors)
        .not_to include Relaton::RequestError
    end

    it "raises with no cache directory at all" do
      expect(Relaton::Iso::Bibliography).not_to receive(:get)
      expect { described_class.new(nil, nil).fetch "ISO 19115-1" }
        .to raise_error Relaton::NotInLocalStoreError
    end

    it "raises from fetch_std" do
      expect { db.fetch_std "ISO 19115-1" }
        .to raise_error Relaton::NotInLocalStoreError
    end

    it "keeps fetch_db's nil answer" do
      expect(db.fetch_db("ISO 19115-1")).to be_nil
    end

    it "passes the error to the fetch_async block" do
      queue = Queue.new
      db.fetch_async("ISO 19115-1") { |r| queue << r }
      expect(queue.pop).to be_a Relaton::NotInLocalStoreError
    end
  end

  context "RELATON_OFFLINE" do
    around do |ex|
      old = ENV.fetch("RELATON_OFFLINE", nil)
      ex.run
    ensure
      ENV["RELATON_OFFLINE"] = old
    end

    it "turns offline mode on" do
      ENV["RELATON_OFFLINE"] = "1"
      expect(described_class.configuration.offline).to be true
    end

    it "is off by default" do
      ENV.delete "RELATON_OFFLINE"
      expect(described_class.configuration.offline).to be false
    end
  end
end
