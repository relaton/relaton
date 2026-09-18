require "tmpdir"
require "json"

RSpec.describe "Relaton index" do
  let(:data_dir) { "spec/index_fixtures/data" }
  let(:dist_dir) { File.expand_path("spec/index_fixtures/dist") }

  around do |example|
    Dir.mktmpdir("index-acc-") do |out|
      @out = out
      Relaton::Cli::FrontendAssets.with_dist_dir(dist_dir) { example.run }
    end
  end

  def shard_files(prefix = "search")
    Dir[File.join(@out, "#{prefix}-*.json")].sort
  end

  it "generates a browsable index site from a data folder" do
    Relaton::Cli.start(["index", data_dir, "-o", @out, "-t", "BIPM Index", "--no-machine-index"])

    index = File.join(@out, "index.html")
    expect(File).to exist(index)
    expect(shard_files).not_to be_empty
    expect(shard_files("detail")).not_to be_empty

    html = File.read(index)
    expect(html).to include('id="relaton-index-app"')
    expect(html).to include('data-total="2"')
    expect(html).to include("BIPM Index")

    records = JSON.parse(File.read(shard_files.first))
    expect(records.size).to eq(2)
    expect(records.first.keys).to contain_exactly("r", "c", "t", "s", "d", "u", "l")
  end

  it "names the machine index from --pubid-flavor" do
    Dir.mktmpdir("acc-pubid-") do |repo|
      FileUtils.mkdir_p(File.join(repo, "data"))
      File.write(File.join(repo, "data", "iso-1.yaml"),
                 "---\ndocidentifier:\n- content: ISO 1234\n  primary: true\n")
      Relaton::Cli.start(["index", File.join(repo, "data"), "-o", @out,
                          "--pubid-flavor", "iso"])

      manifest = JSON.parse(File.read(File.join(@out, "index", "manifest.json")))
      expect(manifest).to include("index" => "index-v2", "key" => "root-number")
      expect(File).to exist(File.join(@out, "index-v2.zip"))
    end
  end

  it "lets --index-name override the derived index name" do
    Dir.mktmpdir("acc-name-") do |repo|
      FileUtils.mkdir_p(File.join(repo, "data"))
      File.write(File.join(repo, "data", "iso-1.yaml"),
                 "---\ndocidentifier:\n- content: ISO 1234\n  primary: true\n")
      Relaton::Cli.start(["index", File.join(repo, "data"), "-o", @out,
                          "--pubid-flavor", "iso", "--index-name", "index-v7"])

      expect(File).to exist(File.join(@out, "index-v7.yaml"))
    end
  end

  # Every data repo publishes a pubid index, so a machine index with no parser
  # would be a plain-string file no consumer narrows on. Raising beats writing
  # one: an unattended deploy that quietly published it would look green.
  it "fails when a machine index is asked for with no pubid flavor" do
    expect { Relaton::Cli.start(["index", data_dir, "-o", @out]) }
      .to raise_error(ArgumentError, /pubid-flavor is required/)

    expect(File).not_to exist(File.join(@out, "index.html"))
  end

  it "honours --shard-size by splitting the corpus across shards" do
    Relaton::Cli.start(["index", data_dir, "-o", @out, "--shard-size", "1", "--no-machine-index"])

    expect(shard_files.map { |f| File.basename(f) })
      .to eq(%w[search-0000.json search-0001.json])
    expect(File.read(File.join(@out, "index.html"))).to include('data-shards="2"')
  end

  it "honours --no-detail" do
    Relaton::Cli.start(["index", data_dir, "-o", @out, "--no-detail", "--no-machine-index"])

    expect(shard_files("detail")).to be_empty
    expect(File.read(File.join(@out, "index.html"))).to include('data-detail-shards="0"')
  end

  it "honours --description and --favicon" do
    Relaton::Cli.start(["index", data_dir, "-o", @out, "--no-machine-index",
                        "--description", "The BIPM standards index.",
                        "--favicon", "https://www.bipm.org/favicon.svg"])

    html = File.read(File.join(@out, "index.html"))
    expect(html).to include('<meta name="description" content="The BIPM standards index.">')
    expect(html).to include(
      '<link rel="icon" href="https://www.bipm.org/favicon.svg" type="image/svg+xml">',
    )
    expect(html).to include('data-description="The BIPM standards index."')
  end

  it "omits the description and favicon tags when the flags are absent" do
    Relaton::Cli.start(["index", data_dir, "-o", @out, "--no-machine-index"])

    html = File.read(File.join(@out, "index.html"))
    expect(html).not_to include('name="description"')
    expect(html).not_to include('rel="icon"')
  end

  # `--mode` was removed. A caller still passing it (relaton/support's
  # data-deploy.yml did, for ~29 repos) must fail LOUDLY: Thor's legacy default
  # is to print the usage error and exit 0, which would publish an empty site
  # from a green CI run. Command.exit_on_failure? is what makes this red.
  it "fails loudly when a caller still passes the removed --mode" do
    expect { Relaton::Cli.start(["index", data_dir, "-o", @out, "--mode", "static-json"]) }
      .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      .and output(/was called with arguments/).to_stderr

    expect(File).not_to exist(File.join(@out, "index.html"))
  end

  context "with a sibling static/ folder" do
    let(:data_dir) { "spec/index_fixtures_static/data" }

    def records
      shard_files.flat_map { |f| JSON.parse(File.read(f)) }
    end

    it "includes the static/ docs in the generated site by default" do
      Relaton::Cli.start(["index", data_dir, "-o", @out, "--no-machine-index"])

      ids = records.map { |r| r["r"] }
      expect(ids).to include("NIST Research Library (2022)")
      expect(ids).to include("JCGM 100 (2008)")
    end

    it "omits the static/ docs with --no-static" do
      Relaton::Cli.start(["index", data_dir, "-o", @out, "--no-static", "--no-machine-index"])

      expect(records.map { |r| r["r"] }).not_to include("NIST Research Library (2022)")
    end
  end
end
