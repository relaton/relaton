require "fileutils"
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

  it "clones an entry and its document into another cache" do
    cache.store pubid("ISO 19115-1"), xml, item_key: pubid("ISO 19115-1:2014")
    other = described_class.new "testcache2"
    other.clone_entry pubid("ISO 19115-1"), cache
    expect(other[pubid("ISO 19115-1")]).to eq xml
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

  it "keeps every row when two processes write" do
    pids = Array.new(2) do |t|
      fork do
        c = described_class.new dir
        25.times { |i| c[pubid("ISO 1#{t}#{i.to_s.rjust(2, '0')}:2014")] = xml }
        exit! 0
      end
    end
    pids.each { Process.wait _1 }
    expect(described_class.new(dir).rows.size).to eq 50
  end
end
