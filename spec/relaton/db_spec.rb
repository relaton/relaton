RSpec.describe Relaton::Db do
  it "returns docid type" do
    FileUtils.rm_rf %w(testcache testcache2)
    db = Relaton::Db.new "testcache", "testcache2"
    expect(db.docid_type("CN(GB/T 1.1)")).to eq ["Chinese Standard", "GB/T 1.1"]
  end

  it "fetch when no local db" do
    FileUtils.rm_rf %w(testcache testcache2)
    db = Relaton::Db.new "testcache", nil
    VCR.use_cassette "iso_19115_1" do
      bib = db.fetch("ISO 19115-1", nil, {})
      expect(bib).to be_instance_of RelatonIsoBib::IsoBibliographicItem
    end
  end
end
