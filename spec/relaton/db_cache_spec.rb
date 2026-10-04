require "fileutils"
require "relaton/db"
require "timeout"

RSpec.describe Relaton::Db::Cache do
  let(:dir) { "testcache" }
  let(:cache) { described_class.new dir }
  let(:xml) do
    <<~XML
      <bibdata><fetched>#{Date.today}</fetched><docidentifier type="ISO" primary="true">ISO 19115-1:2014</docidentifier></bibdata>
    XML
  end

  def pubid(ref)
    require "pubid"
    Pubid::Iso::Identifier.parse ref
  end

  before { FileUtils.rm_rf [dir, "#{dir}-v1.bak", "testcache2"] }
  after { FileUtils.rm_rf [dir, "#{dir}-v1.bak", "testcache2"] }

  it "creates default caches" do
    cache_path = File.expand_path("~/.relaton/cache")
    FileUtils.mv cache_path, "relaton1/cache", force: true
    FileUtils.rm_rf %w(relaton)
    Relaton::Db.init_bib_caches(
      global_cache: true, local_cache: "", flush_caches: true,
    )
    expect(File.exist?(cache_path)).to be true
    expect(File.exist?("relaton")).to be true
    FileUtils.mv "relaton1/cache", cache_path if File.exist? "relaton1"
    FileUtils.rm_rf %w(relaton relaton1)
  end

  context "pubid keys" do
    it "reads back a document by its pubid" do
      cache[pubid("ISO 19115-1:2014")] = xml
      expect(described_class.new(dir)[pubid("ISO 19115-1:2014")]).to eq xml
    end

    it "reads a wrapped string key through the flavor's pubid" do
      cache["ISO(ISO 19115-1:2014)"] = xml
      expect(cache[pubid("ISO 19115-1:2014")]).to eq xml
    end

    it "keeps a not-found marker" do
      cache[pubid("ISO 9999")] = "not_found #{Date.today}"
      expect(cache[pubid("ISO 9999")]).to eq "not_found #{Date.today}"
      expect(cache.fetched(pubid("ISO 9999"))).to eq Date.today.to_s
    end

    it "reads a not-found entry as a typed value" do
      date = (Date.today - 3).to_s
      cache.store pubid("ISO 9999"), Relaton::Db::NotFound.new(fetched: date)
      expect(cache.read(pubid("ISO 9999")))
        .to eq Relaton::Db::NotFound.new(fetched: date)
      expect(cache[pubid("ISO 9999")]).to eq "not_found #{date}"
      expect(cache.fetched(pubid("ISO 9999"))).to eq date
    end

    it "reads a legacy not-found string as a typed value" do
      cache[pubid("ISO 9999")] = "not_found 2026-01-02"
      expect(cache.read(pubid("ISO 9999")))
        .to eq Relaton::Db::NotFound.new(fetched: "2026-01-02")
    end

    it "reads a document as its XML" do
      cache[pubid("ISO 19115-1:2014")] = xml
      expect(cache.read(pubid("ISO 19115-1:2014"))).to eq xml
    end

    it "does not match a dated query to an entry of another year" do
      cache[pubid("ISO 19115-1:2014")] = xml
      expect(cache[pubid("ISO 19115-1:2003")]).to be_nil
    end

    it "does not match an undated query to a dated entry" do
      cache[pubid("ISO 19115-1:2014")] = xml
      expect(cache[pubid("ISO 19115-1")]).to be_nil
    end

    it "matches a dated query to an entry the query is a subset of" do
      cache[pubid("ISO 19115-1:2014(en)")] = xml
      expect(cache[pubid("ISO 19115-1:2014")]).to eq xml
    end

    it "does not match a dated query to another part" do
      cache[pubid("ISO 19115-1:2003")] = xml
      expect(cache[pubid("ISO 19115:2003")]).to be_nil
      expect(cache.candidates(pubid("ISO 19115"))).to be_empty
    end

    it "does not match a base document to its amendment" do
      cache[pubid("ISO 19115-1:2014/Amd 1:2018")] = xml
      expect(cache[pubid("ISO 19115-1:2014")]).to be_nil
    end

    it "matches an undated query with === only for candidates" do
      cache[pubid("ISO 19115-1:2014")] = xml
      expect(cache.candidates(pubid("ISO 19115-1")).map(&:first))
        .to eq [pubid("ISO 19115-1:2014")]
    end
  end

  context "a query row and an item row" do
    it "share one document file" do
      cache.store pubid("ISO 19115-1"), xml, item_key: pubid("ISO 19115-1:2014")
      expect(cache[pubid("ISO 19115-1")]).to eq xml
      expect(cache[pubid("ISO 19115-1:2014")]).to eq xml
      expect(Dir["#{dir}/v2/docs/**/*.xml"].size).to eq 1
    end

    it "keeps the file until the last row is deleted" do
      cache.store pubid("ISO 19115-1"), xml, item_key: pubid("ISO 19115-1:2014")
      cache.delete pubid("ISO 19115-1")
      expect(cache[pubid("ISO 19115-1")]).to be_nil
      expect(cache[pubid("ISO 19115-1:2014")]).to eq xml
      cache.delete pubid("ISO 19115-1:2014")
      expect(Dir["#{dir}/v2/docs/**/*.xml"]).to be_empty
    end

    it "writes one row when the item key equals the query key" do
      cache.store pubid("ISO 19115-1:2014"), xml,
                  item_key: pubid("ISO 19115-1:2014")
      expect(cache.rows.size).to eq 1
    end
  end

  context "when a stale file occupies the cache path" do
    it "replaces it with a working cache directory" do
      stale_path = "testcache-stale"
      FileUtils.rm_rf stale_path
      File.write stale_path, "XXX"
      stale_cache = described_class.new stale_path
      stale_cache[pubid("ISO 19115-1")] = xml
      expect(File.directory?(stale_path)).to be true
      expect(stale_cache[pubid("ISO 19115-1")]).to eq xml
    ensure
      FileUtils.rm_rf stale_path
    end
  end

  context "string keys" do
    it "stores a key no processor owns" do
      cache["test_key"] = xml
      expect(cache["test_key"]).to eq xml
      cache.delete "test_key"
      expect(cache["test_key"]).to be_nil
    end
  end

  it "expires an undated entry after 60 days" do
    old = xml.sub(Date.today.to_s, (Date.today - 61).to_s)
    cache[pubid("ISO 19115-1")] = old
    expect(cache.valid_entry?(pubid("ISO 19115-1"), nil)).to be false
    expect(cache.valid_entry?(pubid("ISO 19115-1"), "2014")).to be_truthy
  end

  it "expires a not_found entry after 60 days, dated or not" do
    key = pubid("ISO 9999:2030")
    cache[key] = "not_found #{Date.today}"
    expect(cache.valid_entry?(key, "2030")).to be_truthy
    cache[key] = "not_found #{Date.today - 61}"
    expect(cache.valid_entry?(key, "2030")).to be false
    expect(cache.valid_entry?(key, nil)).to be false
    cache.expire key, "2030"
    expect(cache[key]).to be_nil
  end

  it "clones an entry and its document into another cache" do
    cache.store pubid("ISO 19115-1"), xml, item_key: pubid("ISO 19115-1:2014")
    other = described_class.new "testcache2"
    other.clone_entry pubid("ISO 19115-1"), cache
    expect(other[pubid("ISO 19115-1")]).to eq xml
  end

  it "keeps the cache's own row when it already has one" do
    cache.store pubid("ISO 19115-1"), xml, item_key: pubid("ISO 19115-1:2014")
    own = xml.sub("ISO 19115-1:2014", "ISO 19115-1:2015")
    other = described_class.new "testcache2"
    other.store pubid("ISO 19115-1"), own
    other.clone_entry pubid("ISO 19115-1"), cache
    expect(other[pubid("ISO 19115-1")]).to eq own
  end

  it "clones a not-found entry with its fetched date" do
    date = (Date.today - 3).to_s
    cache.store pubid("ISO 9999"), Relaton::Db::NotFound.new(fetched: date)
    other = described_class.new "testcache2"
    other.clone_entry pubid("ISO 9999"), cache
    expect(other.read(pubid("ISO 9999")))
      .to eq Relaton::Db::NotFound.new(fetched: date)
  end

  it "lists every document once" do
    cache.store pubid("ISO 19115-1"), xml, item_key: pubid("ISO 19115-1:2014")
    cache["IEC(IEC 60050-102:2007)"] =
      xml.sub("ISO 19115-1:2014", "IEC 60050-102:2007")
    expect(cache.all.size).to eq 2
    flavors = cache.all { |processor, _| processor.short }
    expect(flavors).to match_array %i[relaton_iso relaton_iec]
  end

  it "files an adopted norm under its own flavor, not the adopted one" do
    require "pubid"
    cen = Pubid::CenCenelec::Identifier.parse "CEN ISO/TS 21003-7:2019"
    cache[cen] = xml.sub("ISO 19115-1:2014", "CEN ISO/TS 21003-7:2019")
    expect(cache.all { |processor, _| processor.short }).to eq [:relaton_cen]
  end

  it "moves an old-layout cache aside, never deletes it" do
    FileUtils.mkdir_p "#{dir}/iso"
    File.write "#{dir}/iso/iso_123.xml", "old"
    described_class.new dir
    expect(File.read("#{dir}-v1.bak/iso/iso_123.xml")).to eq "old"
    expect(Dir.exist?("#{dir}/iso")).to be false
  end

  it "moves an old-layout cache aside only once" do
    FileUtils.mkdir_p ["#{dir}/iso", "#{dir}-v1.bak"]
    File.write "#{dir}/iso/iso_123.xml", "old again"
    described_class.new dir
    expect(File.read("#{dir}/iso/iso_123.xml")).to eq "old again"
    expect(Dir["#{dir}-v1.bak*"]).to eq ["#{dir}-v1.bak"]
  end

  it "imports old-layout entries into the v2 stores (relaton#240)" do
    FileUtils.mkdir_p "#{dir}/iso"
    File.write "#{dir}/iso/iso_123.xml", xml.sub("ISO 19115-1:2014", "ISO 123")
    imported = described_class.new dir
    expect(imported[pubid("ISO 123")]).to include "ISO 123"
    expect(File.exist?("#{dir}/v2/.v1-imported")).to be true

    reopened = described_class.new dir
    expect(reopened[pubid("ISO 123")]).to include "ISO 123"
  end

  it "keeps a v2 entry over a re-run import of the same old-layout key" do
    FileUtils.mkdir_p "#{dir}/iso"
    File.write "#{dir}/iso/iso_123.xml", xml.sub("ISO 19115-1:2014", "ISO 123")
    described_class.new dir
    fresh = described_class.new dir
    fresh[pubid("ISO 123")] = xml.sub("ISO 19115-1:2014", "ISO 123 fresh")
    File.delete "#{dir}/v2/.v1-imported" # force the import to run again
    reread = described_class.new dir
    expect(reread[pubid("ISO 123")]).to include "fresh"
  end

  it "drops a flavor's entries when its grammar changes" do
    cache[pubid("ISO 19115-1:2014")] = xml
    cache[pubid("ISO 9999:2020")] = "not_found #{Date.today}"
    processor = Relaton::Db::Registry.instance[:relaton_iso]
    allow(processor).to receive(:grammar_hash).and_return "changed"
    reopened = described_class.new(dir)
    expect(reopened[pubid("ISO 19115-1:2014")]).to be_nil
    expect(reopened[pubid("ISO 9999:2020")]).to be_nil
  end

  it "removes a document no row points to after a row is replaced" do
    cache[pubid("ISO 19115-1")] = xml
    cache.store pubid("ISO 19115-1"), xml, item_key: pubid("ISO 19115-1:2014")
    expect(Dir["#{dir}/v2/docs/**/*.xml"].size).to eq 1
  end

  it "expires the row a dated key matched through ===" do
    old = xml.sub(Date.today.to_s, (Date.today - 61).to_s)
    cache[pubid("ISO 19115-1:2014(en)")] = old
    cache.expire pubid("ISO 19115-1:2014"), nil
    expect(cache.rows).to be_empty
  end

  it "reads the last complete index when a writer died before its rename" do
    cache[pubid("ISO 19115-1:2014")] = xml
    bucket = Dir["#{dir}/v2/rows/**/*.json"].first
    File.write "#{bucket}.tmp.99999.deadbeef", "{ half-written"
    expect(described_class.new(dir)[pubid("ISO 19115-1:2014")]).to eq xml
  end

  it "keeps every row when two threads write" do
    threads = Array.new(2) do |t|
      Thread.new do
        25.times { |i| cache[pubid("ISO #{1000 + (t * 100) + i}:2014")] = xml }
      end
    end
    threads.each(&:join)
    expect(cache.rows.size).to eq 50
  end

  # All the rows go to one bucket (`iso/1000`, one part each), so a lost
  # update shows as a missing row.
  it "keeps every row when two processes write" do
    scripts = Array.new(2) do |t|
      <<~RUBY
        require "relaton/db"
        require "pubid"
        cache = Relaton::Db::Cache.new #{File.expand_path(dir).inspect}
        start_barrier!
        25.times do |i|
          ref = "ISO 1000-#{t}\#{i.to_s.rjust(2, '0')}:2014"
          cache[Pubid::Iso::Identifier.parse(ref)] = #{xml.inspect}
        end
      RUBY
    end
    statuses, logs = run_children scripts
    expect(statuses).to all(be_success), logs.join("\n")
    expect(described_class.new(dir).rows.size).to eq 50
  end
end
