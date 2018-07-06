require "spec_helper"

RSpec.describe Relaton::Db do
  it "rejects an illegal reference prefix" do
    system "rm testcache.json testcache2.json"
    db = Relaton::Db.new("testcache.json", "testcache2.json")
    expect(db.get("XYZ XYZ", nil, {})).to raise_error(RelatonError)
    db.save()
    expect(File.exist?("testcache.json")).to be false
    expect(File.exist?("testcache2.json")).to be false
  end

end
