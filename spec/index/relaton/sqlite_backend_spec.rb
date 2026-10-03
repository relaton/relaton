require "sqlite3"

describe Relaton::Index::SqliteBackend do
  let(:dir) { Dir.mktmpdir }
  let(:db_path) { File.join(dir, "index-v2.db") }

  subject { described_class.new(db_path, pubid_class: TestIdentifier) }

  after do
    subject.close
    FileUtils.remove_entry(dir)
  end

  def row(number, publisher:, num:, file:)
    id = TestIdentifier.create(publisher: publisher, number: num)
    [number, number, { publisher: publisher, number: num }, file]
  end

  it "builds from an enumerator and answers bucket queries" do
    rows = [
      ["1", "1", { publisher: "ISO", number: 1 }, "f1"],
      ["2", "2", { publisher: "ISO", number: 2 }, "f2a"],
      ["2", "2", { publisher: "ISO", number: 2, edition: 2 }, "f2b"],
    ]
    subject.build(rows.each)
    expect(subject.count).to eq 3
    bucket = subject.bucket("2")
    expect(bucket.map { |r| r[:file] }).to contain_exactly("f2a", "f2b")
    expect(bucket.first[:id]).to be_a(Hash)
    expect(subject.bucket("404")).to eq []
  end

  it "rebuilds when the schema version differs" do
    subject.build([["1", "1", { publisher: "ISO", number: 1 }, "f1"]].each)
    subject.send(:meta_set, "schema_version", "0")
    subject.close
    fresh = described_class.new(db_path, pubid_class: TestIdentifier)
    expect(fresh.stale_schema?).to be true
    fresh.close
  end

  it "iterates every row without loading them all" do
    subject.build([["1", "1", { publisher: "ISO", number: 1 }, "f1"],
                   ["2", "2", { publisher: "ISO", number: 2 }, "f2"]].each)
    files = []
    subject.each_row { |r| files << r[:file] }
    expect(files).to contain_exactly("f1", "f2")
  end
end
