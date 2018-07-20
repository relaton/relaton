require "spec_helper"

RSpec.describe Relaton::Db do
  let!(:db) { Relaton::Db.new("testcache", "testcache2") }

  before :each do
    system "rm testcache testcache2"
  end

  it "rejects an illegal reference prefix" do
    expect { db.fetch("XYZ XYZ", nil, {}) }.to output(/does not have a recognised prefix/).to_stderr
    testcache = PStore.new "testcache"
    testcache.transaction do
      expect(testcache.roots.size).to eq 0
    end
    testcache = PStore.new "testcache2"
    testcache.transaction do
      expect(testcache.roots.size).to eq 0
    end
  end

  it "gets an ISO reference and caches it" do
    stub_isobib
    bib = db.fetch("ISO 19115-1", nil, {})
    expect(bib).to be_instance_of IsoBibItem::IsoBibliographicItem
    expect(bib.to_xml).to include "<bibitem type=\"international-standard\" id=\"ISO19115-1\">"
    expect(File.exist?("testcache")).to be true
    expect(File.exist?("testcache2")).to be true
    testcache = PStore.new "testcache"
    testcache.transaction true do
      expect(testcache["ISO 19115-1"]["bib"].to_xml).to include "<bibitem type=\"international-standard\" id=\"ISO19115-1\">"
    end
    testcache = PStore.new "testcache2"
    testcache.transaction do
      expect(testcache["ISO 19115-1"]["bib"].to_xml).to include "<bibitem type=\"international-standard\" id=\"ISO19115-1\">"
    end
  end

  it "deals with a non-existant ISO reference" do
    stub_isobib
    bib = db.fetch("ISO 111111119115-1", nil, {})
    expect(bib).to be_nil
    expect(File.exist?("testcache")).to be true
    expect(File.exist?("testcache2")).to be true
    testcache = PStore.new "testcache"
    testcache.transaction do
      expect(testcache["ISO 111111119115-1"]["fetched"].to_s).to eq Date.today.to_s
      expect(testcache["ISO 111111119115-1"]["bib"]).to eq "not_found"
    end
    testcache = PStore.new "testcache2"
    testcache.transaction do
      expect(testcache["ISO 111111119115-1"]["fetched"].to_s).to eq Date.today.to_s
      expect(testcache["ISO 111111119115-1"]["bib"]).to eq "not_found"
    end
  end

  it "list all elements as a serialization" do
    stub_isobib 2
    db.fetch "ISO 19115-1", nil, {}
    db.fetch "ISO 19115-2", nil, {}
    file = "spec/support/list_entries.xml"
    File.write file, db.to_xml unless File.exist? file
    expect(db.to_xml).to eq File.read file
  end

  it "save/load entry" do
    db.save_entry "test key", value: "test value"
    expect(db.load_entry("test key")[:value]).to eq "test value"
    expect(db.load_entry("not existed key")).to be_nil
  end

  it "get GB reference and cache it" do
    stub_gbbib
    bib = db.fetch "GB/T 20223", "2006", {}
    expect(bib).to be_instance_of Gbbib::GbBibliographicItem
  end

  private

  # @param count [Integer] number of stubbing
  def stub_isobib(count = 1)
    expect(Isobib::IsoBibliography).to receive(:get).and_wrap_original do |m, *args|
      get_resp m, *args
    end.exactly(count).times
  end

  def stub_gbbib(count = 1)
    expect(Gbbib::GbBibliography).to receive(:get).and_wrap_original do |m, *args|
      get_resp m, *args
    end.exactly(count).times
  end

  def get_resp(method, *args)
    expect_args args
    file = "spec/support/" + args[0].downcase.gsub(/[\/\s-]/, "_")
    file += "_#{args[1]}" if args[1]
    store = PStore.new file
    store.transaction do
      store[:resp] = method.call(*args) unless store.root? :resp
      store[:resp]
    end
  end

  def expect_args(args)
    expect(args.size).to eq 3
    expect(args[0]).to be_instance_of String
    expect(args[1]).to be_instance_of(NilClass).or be_instance_of String
    expect(args[2]).to be_instance_of Hash
  end
end
