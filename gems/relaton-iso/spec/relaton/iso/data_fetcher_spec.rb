require "relaton/iso/data_fetcher"
require "fileutils"
require "tmpdir"

describe Relaton::Iso::DataFetcher do
  let(:work_dir) { Dir.mktmpdir }
  let(:output_dir) { File.join(work_dir, "data") }
  let(:last_modified_path) { File.join(work_dir, Relaton::Iso::DataFetcher::LAST_MODIFIED_FILE) }

  let(:sample_records) do
    [
      {
        "id" => 1, "deliverableType" => "IS", "reference" => "ISO 9001:2015",
        "title" => { "en" => "Quality management systems - Requirements" },
        "publicationDate" => "2015-09-01", "edition" => 5,
        "icsCode" => ["03.120.10"], "ownerCommittee" => "ISO/TC 176/SC 2",
        "currentStage" => 9092, "languages" => ["en"], "scope" => { "en" => nil }
      },
      {
        "id" => 2, "deliverableType" => "TR", "reference" => "ISO/TR 17",
        "title" => { "en" => "Vocabulary" },
        "publicationDate" => "2018-01-01", "edition" => 1,
        "icsCode" => nil, "ownerCommittee" => "ISO/TC 1",
        "currentStage" => 6060, "languages" => ["en"], "scope" => { "en" => nil }
      },
    ]
  end

  let(:jsonl_path) do
    p = File.join(work_dir, "fixture.jsonl")
    File.write(p, sample_records.map(&:to_json).join("\n"))
    p
  end

  let(:tc_jsonl_path) do
    p = File.join(work_dir, "tc.jsonl")
    File.write(p, "")
    p
  end

  before do
    @cwd = Dir.pwd
    Dir.chdir(work_dir)
    allow_any_instance_of(described_class).to receive(:download_dataset).and_return(jsonl_path)
    allow_any_instance_of(described_class).to receive(:download_tc_dataset).and_return(tc_jsonl_path)
    allow_any_instance_of(described_class).to receive(:fetch_last_modified).and_return("Wed, 13 May 2026 07:18:23 GMT")
  end

  after do
    Dir.chdir(@cwd)
    FileUtils.rm_rf(work_dir)
  end

  it "initializes" do
    fetcher = described_class.new(output_dir, "bibxml")
    expect(fetcher.instance_variable_get(:@output)).to eq(output_dir)
    expect(fetcher.instance_variable_get(:@format)).to eq("bibxml")
    expect(fetcher.instance_variable_get(:@ext)).to eq("xml")
    expect(fetcher.instance_variable_get(:@files)).to be_a(Set)
  end

  it "ingests records and writes one YAML per primary docid" do
    described_class.fetch("iso-open-data-all", output: output_dir, format: "yaml")
    files = Dir["#{output_dir}/*.yaml"]
    expect(files.size).to eq(2)
    expect(files.find { |f| f.include?("iso-9001-2015") }).not_to be_nil
    expect(files.find { |f| f.include?("iso-tr-17") }).not_to be_nil
  end

  it "writes last_modified.txt after a successful run" do
    described_class.fetch("iso-open-data-all", output: output_dir, format: "yaml")
    expect(File.read(last_modified_path).strip).to eq("Wed, 13 May 2026 07:18:23 GMT")
  end

  it "short-circuits when last-modified is unchanged" do
    File.write(last_modified_path, "Wed, 13 May 2026 07:18:23 GMT")
    FileUtils.mkdir_p(output_dir)
    File.write(File.join(output_dir, "iso-1.yaml"), "stub")
    File.write("#{Relaton::Iso::INDEXFILE}.yaml", "[]")
    expect_any_instance_of(described_class).not_to receive(:download_dataset)
    described_class.fetch("iso-open-data", output: output_dir, format: "yaml")
  end

  it "refreshes even when last-modified matches but the output dir is empty" do
    File.write(last_modified_path, "Wed, 13 May 2026 07:18:23 GMT")
    File.write("#{Relaton::Iso::INDEXFILE}.yaml", "[]")
    described_class.fetch("iso-open-data", output: output_dir, format: "yaml")
    expect(Dir["#{output_dir}/*.yaml"].size).to eq(2)
  end

  it "refreshes even when last-modified matches but the index file is missing" do
    File.write(last_modified_path, "Wed, 13 May 2026 07:18:23 GMT")
    FileUtils.mkdir_p(output_dir)
    File.write(File.join(output_dir, "iso-1.yaml"), "stub")
    expect_any_instance_of(described_class).to receive(:ingest_records).and_call_original
    described_class.fetch("iso-open-data", output: output_dir, format: "yaml")
  end

  it "iso-open-data-all ignores the Last-Modified short-circuit" do
    File.write(last_modified_path, "Wed, 13 May 2026 07:18:23 GMT")
    FileUtils.mkdir_p(output_dir)
    File.write(File.join(output_dir, "iso-1.yaml"), "stub")
    File.write("#{Relaton::Iso::INDEXFILE}.yaml", "[]")
    expect_any_instance_of(described_class).to receive(:ingest_records).and_call_original
    described_class.fetch("iso-open-data-all", output: output_dir, format: "yaml")
  end

  it "fetch returns false when up to date and true when it rebuilds" do
    File.write(last_modified_path, "Wed, 13 May 2026 07:18:23 GMT")
    FileUtils.mkdir_p(output_dir)
    File.write(File.join(output_dir, "iso-1.yaml"), "stub")
    File.write("#{Relaton::Iso::INDEXFILE}.yaml", "[]")
    expect(described_class.fetch("iso-open-data", output: output_dir, format: "yaml"))
      .to be(false)
    expect(described_class.fetch("iso-open-data-all", output: output_dir, format: "yaml"))
      .to be(true)
  end

  it "a proceeding run does a full replace: clears stale files and resets the index" do
    # A changed Last-Modified (or -all) means a full rebuild, so files and index
    # entries for records that have left the feed must not survive.
    FileUtils.mkdir_p(output_dir)
    stale = File.join(output_dir, "stale.yaml")
    File.write(stale, "stale")
    Relaton::Index.pool.remove(:iso) # force a fresh read of the on-disk index
    seed = Relaton::Index::Type.new(
      :iso, nil, "#{Relaton::Iso::INDEXFILE}.yaml", nil, ::Pubid::Iso::Identifier,
    )
    seed.add_or_update(
      ::Pubid::Iso::Identifier.parse("ISO/DIS 9999"), "data/iso-dis-9999.yaml",
    )
    seed.save

    described_class.fetch("iso-open-data-all", output: output_dir, format: "yaml")

    expect(File.exist?(stale)).to be(false)
    index = YAML.safe_load(
      File.read("#{Relaton::Iso::INDEXFILE}.yaml"), permitted_classes: [Symbol],
    )
    files = index.map { |e| e[:file] }
    expect(files).not_to include("data/iso-dis-9999.yaml")
    expect(files.size).to eq(2) # only the two current feed records remain
  end

  describe "#normalize_reference" do
    let(:fetcher) { described_class.new(output_dir, "yaml") }

    it "drops `Withdrawn` deleted-project references" do
      expect(fetcher.send(:normalize_reference, "Withdrawn 1701/Add 1"))
        .to be_nil
    end

    it "leaves a normal reference untouched" do
      expect(fetcher.send(:normalize_reference, "ISO 9001:2015"))
        .to eq("ISO 9001:2015")
    end

    it "returns nil for nil or empty input" do
      expect(fetcher.send(:normalize_reference, nil)).to be_nil
      expect(fetcher.send(:normalize_reference, "")).to be_nil
    end
  end

  context "withdrawn (deleted-project) records" do
    let(:sample_records) do
      [
        {
          "id" => 100, "deliverableType" => "IS",
          "reference" => "Withdrawn 1701/Add 1",
          "title" => { "en" => "Old" },
          "publicationDate" => nil, "currentStage" => 3098,
          "languages" => ["en"]
        },
        {
          "id" => 101, "deliverableType" => "IS", "reference" => "ISO 1701",
          "title" => { "en" => "New" }, "publicationDate" => "1995-01-01",
          "currentStage" => 6060, "languages" => ["en"],
          "replaces" => [100]
        },
      ]
    end

    it "skips Withdrawn records and drops them from relations" do
      described_class.fetch("iso-open-data-all", output: output_dir, format: "yaml")

      files = Dir["#{output_dir}/*.yaml"]
      expect(files.size).to eq(1)

      item = Relaton::Iso::Item.from_yaml(File.read(files.first))
      expect(item.relation.find { |r| r.type == "obsoletes" }).to be_nil
    end
  end

  context "#rewrite_with_same_or_newer" do
    let(:fetcher) { described_class.new(output_dir, "yaml") }
    let(:newer) do
      Relaton::Iso::DataParser.new(
        sample_records[0].merge("edition" => 6), {}, Hash.new(true),
      ).parse
    end
    let(:older) do
      Relaton::Iso::DataParser.new(sample_records[0], {}, Hash.new(true)).parse
    end

    before { FileUtils.mkdir_p(output_dir) }

    it "rewrites when the new edition is greater" do
      file = File.join(output_dir, "iso-9001-2015.yaml")
      File.write(file, older.to_yaml)
      docid = newer.docidentifier.find(&:primary)
      fetcher.send(:rewrite_with_same_or_newer, newer, docid, file)
      expect(Relaton::Iso::Item.from_yaml(File.read(file)).edition.content).to eq("6")
    end

    it "does not overwrite when the on-disk record is newer" do
      file = File.join(output_dir, "iso-9001-2015.yaml")
      File.write(file, newer.to_yaml)
      docid = older.docidentifier.find(&:primary)
      fetcher.send(:rewrite_with_same_or_newer, older, docid, file)
      expect(Relaton::Iso::Item.from_yaml(File.read(file)).edition.content).to eq("6")
    end
  end

  describe "#download_jsonl" do
    let(:fetcher) { described_class.new(output_dir, "yaml") }
    let(:url) { "https://example.com/iso/data.jsonl" }
    let(:filename) { "data_fetcher_spec_download.jsonl" }
    let(:tmp_path) { File.join(Dir.tmpdir, filename) }

    before { allow(fetcher).to receive(:sleep) }
    after  { FileUtils.rm_f(tmp_path) }

    it "retries on transient HTTP failure and eventually succeeds" do
      stub_request(:get, url).to_return(
        { status: 403, body: "" },
        { status: 503, body: "" },
        { status: 200, body: "ok\n" },
      )

      path = fetcher.send(:download_jsonl, url, filename)

      expect(path).to eq(tmp_path)
      expect(File.read(path)).to eq("ok\n")
      expect(a_request(:get, url)).to have_been_made.times(3)
      expect(fetcher).to have_received(:sleep).with(30).ordered
      expect(fetcher).to have_received(:sleep).with(60).ordered
    end

    it "raises after exhausting retries on persistent HTTP failure" do
      stub_request(:get, url).to_return(status: 403, body: "")

      expect { fetcher.send(:download_jsonl, url, filename) }
        .to raise_error(RuntimeError, /Open Data download failed: HTTP 403/)

      total = described_class::MAX_DOWNLOAD_RETRIES + 1
      expect(a_request(:get, url)).to have_been_made.times(total)
      expect(fetcher).to have_received(:sleep).exactly(described_class::MAX_DOWNLOAD_RETRIES).times
    end
  end

  describe "#index_primary (unparseable primary id handling)" do
    let(:fetcher) { described_class.new(output_dir, "yaml") }
    let(:index_double) { double("index") }

    before { allow(fetcher).to receive(:index).and_return(index_double) }

    it "indexes the parsed pubid" do
      pubid = Pubid::Iso::Identifier.parse("ISO 9001:2015")
      docid = double(pubid: pubid, content: "ISO 9001:2015")
      expect(index_double).to receive(:add_or_update).with(pubid, "f.yaml")
      fetcher.send(:index_primary, docid, "f.yaml")
      expect(fetcher.send(:unparseable_ids)).to be_empty
    end

    it "records an unparseable id instead of indexing a raw string" do
      docid = double(pubid: nil, content: "ISO/IEC 9579/WD Amd")
      expect(index_double).not_to receive(:add_or_update)
      fetcher.send(:index_primary, docid, "iso-iec-9579-wd-amd.yaml")
      expect(fetcher.send(:unparseable_ids))
        .to eq([["ISO/IEC 9579/WD Amd", "iso-iec-9579-wd-amd.yaml"]])
    end

    it "reports recorded unparseable ids through the error machinery" do
      fetcher.send(:unparseable_ids) << ["ISO/IEC 9579/WD Amd", "f.yaml"]
      allow(fetcher).to receive(:gh_issue)
      allow(fetcher).to receive(:log_error)
      fetcher.send(:report_errors)
      expect(fetcher).to have_received(:log_error)
        .with(%r{Unparseable primary id `ISO/IEC 9579/WD Amd`.*f\.yaml})
    end
  end
end
