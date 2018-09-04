require "spec_helper"

RSpec.describe Relaton::Db do
  # let!(:db) { Relaton::Db.new("testcache", "testcache2") }

  before :each do
    system "rm testcache testcache2"
    @db = Relaton::Db.new "testcache", "testcache2"
  end

  it "rejects an illegal reference prefix" do
    expect { @db.fetch("XYZ XYZ", nil, {}) }.to output(/does not have a recognised prefix/).to_stderr
    testcache = PStore.new "testcache"
    testcache.transaction do
      expect(testcache.roots.size).to eq 1
    end
    testcache = PStore.new "testcache2"
    testcache.transaction do
      expect(testcache.roots.size).to eq 1
    end
  end

  it "gets an ISO reference and caches it" do
    stub_bib Isobib::IsoBibliography
    bib = @db.fetch("ISO 19115-1", nil, {})
    expect(bib).to be_instance_of IsoBibItem::IsoBibliographicItem
    expect(bib.to_xml).to include "<bibitem type=\"international-standard\" id=\"ISO19115-1\">"
    expect(File.exist?("testcache")).to be true
    expect(File.exist?("testcache2")).to be true
    testcache = PStore.new "testcache"
    testcache.transaction true do
      expect(testcache["ISO(ISO 19115-1)"]["bib"].to_xml).to include "<bibitem type=\"international-standard\" id=\"ISO19115-1\">"
    end
    testcache = PStore.new "testcache2"
    testcache.transaction do
      expect(testcache["ISO(ISO 19115-1)"]["bib"].to_xml).to include "<bibitem type=\"international-standard\" id=\"ISO19115-1\">"
    end
  end

  it "deals with a non-existant ISO reference" do
    stub_bib Isobib::IsoBibliography
    bib = @db.fetch("ISO 111111119115-1", nil, {})
    expect(bib).to be_nil
    expect(File.exist?("testcache")).to be true
    expect(File.exist?("testcache2")).to be true
    testcache = PStore.new "testcache"
    testcache.transaction do
      expect(testcache["ISO(ISO 111111119115-1)"]["fetched"].to_s).to eq Date.today.to_s
      expect(testcache["ISO(ISO 111111119115-1)"]["bib"]).to eq "not_found"
    end
    testcache = PStore.new "testcache2"
    testcache.transaction do
      expect(testcache["ISO(ISO 111111119115-1)"]["fetched"].to_s).to eq Date.today.to_s
      expect(testcache["ISO(ISO 111111119115-1)"]["bib"]).to eq "not_found"
    end
  end

  it "list all elements as a serialization" do
    stub_bib Isobib::IsoBibliography, 2
    @db.fetch "ISO 19115-1", nil, {}
    @db.fetch "ISO 19115-2", nil, {}
    file = "spec/support/list_entries.xml"
    File.write file, @db.to_xml unless File.exist? file
    expect(@db.to_xml).to eq File.read file
  end

  it "save/load entry" do
    @db.save_entry "test key", value: "test value"
    expect(@db.load_entry("test key")[:value]).to eq "test value"
    expect(@db.load_entry("not existed key")).to be_nil
  end

  it "get GB reference and cache it" do
    stub_bib Gbbib::GbBibliography
    bib = @db.fetch "CN(GB/T 20223)", "2006", {}
    expect(bib).to be_instance_of Gbbib::GbBibliographicItem
    expect(bib.to_xml).to include "<bibitem type=\"standard\" id=\"GB/T20223\">"
    expect(File.exist?("testcache")).to be true
    expect(File.exist?("testcache2")).to be true
    testcache = PStore.new "testcache"
    testcache.transaction true do
      expect(testcache["CN(GB/T 20223:2006)"]["bib"].to_xml).to include "<bibitem type=\"standard\" id=\"GB/T20223\">"
    end
    testcache = PStore.new "testcache2"
    testcache.transaction do
      expect(testcache["CN(GB/T 20223:2006)"]["bib"].to_xml).to include "<bibitem type=\"standard\" id=\"GB/T20223\">"
    end
  end

  it "get RFC reference and cache it" do
    stub_bib RfcBib::RfcBibliography
    bib = @db.fetch "RFC 8341", nil, {}
    expect(bib).to be_instance_of IsoBibItem::BibliographicItem
    expect(bib.to_xml).to include "<bibitem id=\"RFC8341\">"
    expect(File.exist?("testcache")).to be true
    expect(File.exist?("testcache2")).to be true
    testcache = PStore.new "testcache"
    testcache.transaction true do
      expect(testcache["IETF(RFC 8341)"]["bib"].to_xml).to include "<bibitem id=\"RFC8341\">"
    end
    testcache = PStore.new "testcache2"
    testcache.transaction do
      expect(testcache["IETF(RFC 8341)"]["bib"].to_xml).to include "<bibitem id=\"RFC8341\">"
    end
  end

  it "shoul clear global cache if version is changed" do
    @db.save_entry "test_key", value: "test_value"
    expect(File.exist?("testcache")).to be_truthy
    expect(File.exist?("testcache2")).to be_truthy
    stub_const "Relaton::VERSION", "new_version"
    db = Relaton::Db.new "testcache", "testcache2"
    testcache = db.instance_variable_get :@db
    testcache.transaction do
      expect(testcache.root?("test_key")).to be_falsey
    end
    testcache = db.instance_variable_get :@local_db
    expect(testcache).to be_nil
  end

  private

  # @param count [Integer] number of stubbing
  def stub_bib(bib_type, count = 1)
    expect(bib_type).to receive(:get).and_wrap_original do |m, *args|
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
