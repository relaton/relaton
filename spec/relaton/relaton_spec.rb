require "spec_helper"
require "fileutils"

RSpec.describe Relaton::Db do
  # let!(:db) { Relaton::Db.new("testcache", "testcache2") }

  before :each do
    FileUtils.rm_rf %w(testcache testcache2)
    @db = Relaton::Db.new "testcache", "testcache2"
  end

  it "rejects an illegal reference prefix" do
    expect { @db.fetch("XYZ XYZ", nil, {}) }.to output(/does not have a recognised prefix/).to_stderr
  end

  it "gets an ISO reference and caches it" do
    # stub_bib Isobib::IsoBibliography
    VCR.use_cassette "iso_19115_1" do
      bib = @db.fetch("ISO 19115-1", nil, {})
      expect(bib).to be_instance_of IsoBibItem::IsoBibliographicItem
      expect(bib.to_xml).to include "<bibitem type=\"international-standard\" id=\"ISO19115-1\">"
      expect(File.exist?("testcache")).to be true
      expect(File.exist?("testcache2")).to be true
      testcache = Relaton::DbCache.new "testcache"
      expect(testcache["ISO(ISO 19115-1)"]).to include "<bibitem type=\"international-standard\" id=\"ISO19115-1\">"
      testcache = Relaton::DbCache.new "testcache2"
      expect(testcache["ISO(ISO 19115-1)"]).to include "<bibitem type=\"international-standard\" id=\"ISO19115-1\">"
    end
  end

  it "gets an ISO reference with year in code" do
    VCR.use_cassette "19133_2005" do
      bib = @db.fetch("ISO 19133:2005")
      expect(bib).to be_instance_of IsoBibItem::IsoBibliographicItem
      expect(bib.to_xml).to include "<bibitem type=\"international-standard\" id=\"ISO19133\">"
    end
  end

  it "deals with a non-existant ISO reference" do
    # stub_bib Isobib::IsoBibliography
    VCR.use_cassette "iso_111111119115_1" do
      bib = @db.fetch("ISO 111111119115-1", nil, {})
      expect(bib).to be_nil
      expect(File.exist?("testcache")).to be true
      expect(File.exist?("testcache2")).to be true
      testcache = Relaton::DbCache.new "testcache"
      expect(testcache.fetched("ISO(ISO 111111119115-1)")).to eq Date.today.to_s
      expect(testcache["ISO(ISO 111111119115-1)"]).to include "not_found"
      testcache = Relaton::DbCache.new "testcache2"
      expect(testcache.fetched("ISO(ISO 111111119115-1)")).to eq Date.today.to_s
      expect(testcache["ISO(ISO 111111119115-1)"]).to include "not_found"
    end
  end

  it "list all elements as a serialization" do
    # stub_bib Isobib::IsoBibliography, 2
    VCR.use_cassette "iso_19115_1_2", match_requests_on: [:path] do
      @db.fetch "ISO 19115-1", nil, {}
      @db.fetch "ISO 19115-2", nil, {}
    end
    # file = "spec/support/list_entries.xml"
    # File.write file, @db.to_xml unless File.exist? file
    docs = Nokogiri::XML @db.to_xml
    expect(docs.xpath("/documents/bibitem").size).to eq 2
  end

  it "save/load/delete entry" do
    @db.save_entry "test key", "test value"
    expect(@db.load_entry("test key")).to eq "test value"
    expect(@db.load_entry("not existed key")).to be_nil
    testcache = Relaton::DbCache.new "testcache"
    testcache.delete("test_key")
    testcache2 = Relaton::DbCache.new "testcache2"
    testcache2.delete("test_key")
    expect(@db.load_entry("test key")).to be_nil
  end

  it "get GB reference and cache it" do
    # stub_bib Gbbib::GbBibliography
    VCR.use_cassette "gb_t_20223_2006" do
      bib = @db.fetch "CN(GB/T 20223)", "2006", {}
      expect(bib).to be_instance_of Gbbib::GbBibliographicItem
      expect(bib.to_xml).to include "<bibitem type=\"standard\" id=\"GB/T20223\">"
      expect(File.exist?("testcache")).to be true
      expect(File.exist?("testcache2")).to be true
      testcache = Relaton::DbCache.new "testcache"
      expect(testcache["CN(GB/T 20223:2006)"]).to include "<bibitem type=\"standard\" id=\"GB/T20223\">"
      testcache = Relaton::DbCache.new "testcache2"
      expect(testcache["CN(GB/T 20223:2006)"]).to include "<bibitem type=\"standard\" id=\"GB/T20223\">"
    end
  end

  it "get RFC reference and cache it" do
    # stub_bib IETFBib::RfcBibliography
    VCR.use_cassette "rfc_8341" do
      bib = @db.fetch "RFC 8341", nil, {}
      expect(bib).to be_instance_of IsoBibItem::BibliographicItem
      expect(bib.to_xml).to include "<bibitem id=\"RFC8341\">"
      expect(File.exist?("testcache")).to be true
      expect(File.exist?("testcache2")).to be true
      testcache = Relaton::DbCache.new "testcache"
      expect(testcache["IETF(RFC 8341)"]).to include "<bibitem id=\"RFC8341\">"
      testcache = Relaton::DbCache.new "testcache2"
      expect(testcache["IETF(RFC 8341)"]).to include "<bibitem id=\"RFC8341\">"
    end
  end

  it "shoul clear global cache if version is changed" do
    @db.save_entry "test_key", value: "test_value"
    expect(File.exist?("testcache")).to be_truthy
    expect(File.exist?("testcache2")).to be_truthy
    stub_const "Relaton::VERSION", "new_version"
    db = Relaton::Db.new "testcache", "testcache2"
    testcache = db.instance_variable_get :@db
    expect(testcache.all.any?).to be_falsey
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
    file += ".xml"
    File.write file, method.call(*args)&.to_xml, encoding: "utf-8" unless File.exist? file
    File.read file, encoding: "utf-8"
  end

  def expect_args(args)
    expect(args.size).to eq 3
    expect(args[0]).to be_instance_of String
    expect(args[1]).to be_instance_of(NilClass).or be_instance_of String
    expect(args[2]).to be_instance_of Hash
  end
end
