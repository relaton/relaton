require "spec_helper"

RSpec.describe Relaton::Db do
  it "rejects an illegal reference prefix" do
    system "rm testcache testcache2"
    db = Relaton::Db.new("testcache", "testcache2")
    expect { db.fetch("XYZ XYZ", nil, {}) }.to output(/does not have a recognised prefix/).to_stderr
    # expect(File.exist?("testcache")).to be true
    # expect(File.exist?("testcache2")).to be true
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
    system "rm testcache testcache2"
    db = Relaton::Db.new("testcache", "testcache2")
    bib = db.fetch("ISO 19115-1", nil, {})
    db.fetch("ISO 19115-1", nil, {})
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
    system "rm testcache testcache2"
    db = Relaton::Db.new("testcache", "testcache2")
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
    system "rm testcache testcache2"
    db = Relaton::Db.new("testcache", "testcache2")
    db.fetch "ISO 19115-1", nil, {}
    db.fetch "ISO 19115-2", nil, {}
    file = "spec/support/list_entries.xml"
    File.write file, db.to_xml unless File.exist? file
    expect(db.to_xml).to eq File.read file
  end

  it "save/load entry" do
    system "rm testcache testcache2"
    db = Relaton::Db.new "testcache", "testcache2"
    db.save_entry "test key", value: "test value"
    expect(db.load_entry("test key")[:value]).to eq "test value"
    expect(db.load_entry("not existed key")).to be_nil
  end

  private

  def stub_isobib(count = 1)
    expect(Isobib::IsoBibliography).to receive(:get).and_wrap_original do |m, *args|
      expect(args.size).to eq 3
      expect(args[0]).to be_instance_of String
      expect(args[1]).to be_instance_of NilClass
      expect(args[2]).to be_instance_of Hash
      file = "spec/support/" + args[0].downcase.gsub(/[\s-]/, "_") + ".xml"
      File.write file, m.call(*args).to_xml unless File.exist? file
      resp = File.read file
      resp.empty? ? nil : IsoBibItem.from_xml(resp)
    end.exactly(count).times
  end
end
