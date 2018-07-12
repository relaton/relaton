require "spec_helper"

RSpec.describe Relaton::Db do
  it "rejects an illegal reference prefix" do
    system "rm testcache.json testcache2.json"
    db = Relaton::Db.new("testcache.json", "testcache2.json")
    expect{ db.fetch("XYZ XYZ", nil, {}) }.to output(/does not have a recognised prefix/).to_stderr
    db.save
    expect(File.exist?("testcache.json")).to be true
    expect(File.exist?("testcache2.json")).to be true
    testcache = File.read "testcache.json"
    expect(testcache).to eq "{}"
    testcache = File.read "testcache2.json"
    expect(testcache).to eq "{}"
  end

  it "gets an ISO reference and caches it" do
    stub_isobib
    system "rm testcache.json testcache2.json"
    db = Relaton::Db.new("testcache.json", "testcache2.json")
    bib = db.fetch("ISO 19115-1", nil, {})
    expect(bib).to include "<bibitem type=\"international-standard\" id=\"ISO19115-1\">"
    db.save
    expect(File.exist?("testcache.json")).to be true
    expect(File.exist?("testcache2.json")).to be true
    testcache = File.read "testcache.json"
    expect(testcache).to include "<bibitem type=\\\"international-standard\\\" id=\\\"ISO19115-1\\\">"
    testcache = File.read "testcache2.json"
    expect(testcache).to include "<bibitem type=\\\"international-standard\\\" id=\\\"ISO19115-1\\\">"
  end

  it "deals with a non-existant ISO reference" do
    stub_isobib
    system "rm testcache.json testcache2.json"
    db = Relaton::Db.new("testcache.json", "testcache2.json")
    bib = db.fetch("ISO 111111119115-1", nil, {})
    expect(bib).to be_nil
    db.save()
    expect(File.exist?("testcache.json")).to be true
    expect(File.exist?("testcache2.json")).to be true
    testcache = File.read "testcache.json"
    expect(testcache).to include %("ISO 111111119115-1":{"fetched":"#{Date.today}","bib":"not_found"})
    testcache = File.read "testcache2.json"
    expect(testcache).to include %("ISO 111111119115-1":{"fetched":"#{Date.today}","bib":"not_found"})
  end

  private

  def stub_isobib
    expect(Isobib::IsoBibliography).to receive(:get).and_wrap_original do |m, *args|
      expect(args.size).to eq 3
      expect(args[0]).to be_instance_of String
      expect(args[1]).to be_instance_of NilClass
      expect(args[2]).to be_instance_of Hash
      file = "spec/support/" + args[0].downcase.gsub(/[\s-]/, "_") + ".xml"
      File.write file, m.call(*args) unless File.exist? file
      resp = File.read file
      resp.empty? ? nil : resp
    end
  end
end
