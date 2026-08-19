require "tmpdir"
require "json"
require "zlib"
require "relaton/cli/index_site_generator"

RSpec.describe Relaton::Cli::IndexSiteGenerator do
  let(:data_dir) { "spec/index_fixtures/data" }
  let(:dist_dir) { File.expand_path("spec/index_fixtures/dist") }

  # Point FrontendAssets at the fixture bundle so specs never need a Node build.
  around do |example|
    Dir.mktmpdir("index-spec-") do |out|
      @out = out
      Relaton::Cli::FrontendAssets.with_dist_dir(dist_dir) { example.run }
    end
  end

  def generate(opts = {})
    described_class.generate(
      data_dir,
      { output: @out, title: "BIPM Index", generated: "2026-01-01",
        base_url: "https://raw.githubusercontent.com/relaton/relaton-data-bipm/v2" }.merge(opts),
    )
    File.read(File.join(@out, "index.html"), encoding: "utf-8")
  end


  # --- machine index (index/manifest.json + hash shards) ------------------

  def manifest
    JSON.parse(File.read(File.join(@out, "index", "manifest.json")))
  end

  def machine_shards
    Dir[File.join(@out, "index", "shard-*.json")].sort
  end

  def all_machine_records
    machine_shards.flat_map { |f| JSON.parse(File.read(f)) }
  end

  it "emits a manifest describing the sharding contract" do
    generate

    m = manifest
    expect(m).to include(
      "version" => 1, "algorithm" => "crc32",
      "shards" => 256, "count" => anything, "generated" => "2026-01-01",
    )
  end

  it "puts every document in exactly one shard, at crc32(id) % shards" do
    with_corpus(40) do
    end

    records = all_machine_records
    expect(records.size).to eq(40)

    records.each do |rec|
      shard = format("shard-%03d.json", Zlib.crc32(rec["id"]) % 256)
      expect(File).to exist(File.join(@out, "index", shard))
    end
    ids = records.map { |r| r["id"] }
    expect(ids.uniq.size).to eq(ids.size)
  end

  it "carries the index-v1 row shape: rendered docid -> yaml path" do
    with_corpus(3) do
    end

    rec = all_machine_records.find { |r| r["id"] == "DOC 001" }
    expect(rec["file"]).to eq("data/doc-001.yaml")
  end

  it "declares the corpus size in the manifest" do
    with_corpus(7) do
    end

    expect(manifest["count"]).to eq(7)
  end

  it "writes no empty shards" do
    with_corpus(3) do
    end

    machine_shards.each do |f|
      expect(JSON.parse(File.read(f))).not_to be_empty
    end
  end

  it "can be disabled with machine_index: false" do
    generate(machine_index: false)

    expect(File).not_to exist(File.join(@out, "index", "manifest.json"))
    expect(machine_shards).to be_empty
  end


  it "also publishes the monolithic index-v1.yaml in the fleet format" do
    with_corpus(5) do
      rows = YAML.safe_load(File.read(File.join(@out, "index-v1.yaml")), permitted_classes: [Symbol], aliases: true)
      expect(rows.size).to eq(5)
      row = rows.find { |r| r[:id] == "DOC 001" }
      expect(row).to eq(id: "DOC 001", file: "data/doc-001.yaml")
    end
  end

  it "does not copy the corpus by default" do
    with_corpus(3) do
      expect(File).not_to exist(File.join(@out, "data", "doc-001.yaml"))
    end
  end

  it "copies the corpus onto the site with publish_data: true" do
    with_corpus(3, publish_data: true) do
      copied = File.join(@out, "data", "doc-002.yaml")
      expect(File).to exist(copied)
      expect(File.read(copied)).to include("Document 2", "DOC 002")
    end
  end


  it "keeps machine rows repo-relative even when --base-url is set" do
    with_corpus(3, base_url: "https://relaton.github.io/relaton-data-x") do
      all_machine_records.each do |rec|
        expect(rec["file"]).to start_with("data/")
        expect(rec["file"]).not_to include("http")
      end
      # while the UI-facing search shard links are absolutized
      expect(summary_records.first["u"]).to start_with("https://relaton.github.io/")
    end
  end


  it "emits a 404 fallback that forwards /doc/<id> paths into the app" do
    generate

    fallback = File.join(@out, "404.html")
    expect(File).to exist(fallback)
    expect(File.read(fallback)).to include("location.replace")
  end

  # --- shard readers -------------------------------------------------------

  def shard_files(prefix = "search")
    Dir[File.join(@out, "#{prefix}-*.json")].sort
  end

  # Every summary record, in corpus order (shards concatenate in file order).
  def summary_records
    shard_files.flat_map { |f| JSON.parse(File.read(f)) }
  end

  # Every detail slot, in corpus order — including the nils for docs that have
  # no detail fields, since position is what the frontend indexes by.
  def detail_slots
    shard_files("detail").flat_map { |f| JSON.parse(File.read(f)) }
  end

  def attr(html, name)
    html[/\sdata-#{name}="([^"]*)"/, 1]
  end

  # Write `n` trivial documents into a fresh repo and index them.
  def with_corpus(count, opts = {})
    Dir.mktmpdir("corpus-") do |repo|
      FileUtils.mkdir_p(File.join(repo, "data"))
      (1..count).each do |i|
        File.write(
          File.join(repo, "data", format("doc-%03d.yaml", i)),
          "---\ndocidentifier:\n- content: DOC #{format('%03d', i)}\n  primary: true\n" \
          "title:\n- content: Document #{i}\n  language: en\n  type: main\n",
        )
      end
      described_class.generate(
        File.join(repo, "data"),
        { output: @out, generated: "2026-01-01" }.merge(opts),
      )
      yield File.read(File.join(@out, "index.html"), encoding: "utf-8")
    end
  end

  it "returns the path to index.html" do
    path = described_class.generate(data_dir, output: @out, generated: "2026-01-01")
    expect(path).to eq(File.join(@out, "index.html"))
  end

  it "skips the machine index-v*.yaml and indexes only documents" do
    generate
    # 2 documents (ccri/21, cgpm/26); index-v1.yaml is skipped.
    expect(summary_records.size).to eq(2)
  end

  it "renders the rendered primary DocID and title from the document itself" do
    generate
    ccri = summary_records.find { |r| r["r"] == "CCRI 21st Meeting (2009)" }
    expect(ccri).not_to be_nil
    expect(ccri["c"]).to include("21st meeting of the CCRI")
  end

  it "builds the raw-YAML link from base_url + repo-relative path" do
    generate
    expect(summary_records.map { |r| r["u"] }).to include(
      "https://raw.githubusercontent.com/relaton/relaton-data-bipm/v2/data/ccri/meeting/21.yaml",
    )
  end

  it "inlines the compiled bundle (IIFE + CSS)" do
    html = generate
    expect(html).to include("fake IIFE for specs")
    expect(html).to include("fake style for specs")
    expect(html).to include('id="relaton-index-app"')
  end

  # --- the shell carries no document data ----------------------------------

  context "the page shell" do
    it "carries no crawler DOM and no embedded payload" do
      html = generate
      expect(html).not_to include("window.RELATON_INDEX_DATA")
      expect(html).not_to include('class="document"')
      expect(html).not_to include("data-src=")
    end

    it "does not write a monolithic search.json" do
      generate
      expect(File).not_to exist(File.join(@out, "search.json"))
    end

    it "matches the recorded golden shell" do
      golden = File.expand_path("spec/index_fixtures/golden/index.html")
      expect(generate).to eq(File.read(golden, encoding: "utf-8"))
    end
  end

  # --- mount-node scalars: the only index-shape contract -------------------

  context "mount-node scalars" do
    it "reports the corpus total and the shard counts actually on disk" do
      html = generate
      expect(attr(html, "total")).to eq("2")
      expect(attr(html, "shards")).to eq(shard_files.size.to_s)
      expect(attr(html, "detail-shards")).to eq(shard_files("detail").size.to_s)
    end

    it "reports the configured shard sizes" do
      html = generate(shard_size: 5000, detail_shard_size: 500)
      expect(attr(html, "shard-size")).to eq("5000")
      expect(attr(html, "detail-shard-size")).to eq("500")
    end

    it "keeps the counts honest when the corpus spans several shards" do
      with_corpus(7, shard_size: 3, detail_shard_size: 2) do |html|
        expect(attr(html, "total")).to eq("7")
        expect(attr(html, "shards")).to eq("3")
        expect(shard_files.size).to eq(3)
      end
    end
  end

  # --- sharding ------------------------------------------------------------

  context "summary shards" do
    it "splits at shard_size and names them zero-padded in order" do
      with_corpus(7, shard_size: 3) do
        expect(shard_files.map { |f| File.basename(f) })
          .to eq(%w[search-0000.json search-0001.json search-0002.json])
        expect(shard_files.map { |f| JSON.parse(File.read(f)).size }).to eq([3, 3, 1])
      end
    end

    it "preserves corpus order across the shard boundary" do
      with_corpus(7, shard_size: 3) do
        expect(summary_records.map { |r| r["r"] })
          .to eq((1..7).map { |i| "DOC #{format('%03d', i)}" })
      end
    end

    it "emits no trailing empty shard when the count divides exactly" do
      with_corpus(6, shard_size: 3) do
        expect(shard_files.size).to eq(2)
        expect(summary_records.size).to eq(6)
      end
    end

    it "keeps records summary-only, with exactly the seven compact keys" do
      generate
      expect(summary_records.first.keys)
        .to contain_exactly("r", "c", "t", "s", "d", "u", "l")
    end
  end

  context "detail shards" do
    it "carries the rich fields keyed by id, and nothing from the summary" do
      generate
      ccri = detail_slots.compact.find { |e| e["r"] == "CCRI 21st Meeting (2009)" }
      expect(ccri["languages"]).to eq(%w[en fr])
      expect(ccri["publisher"]).to eq("International Bureau of Weights and Measures")
      expect(ccri["docids"]).to include(a_hash_including("id" => "CCRI 21st Meeting (2009)"))
      expect(ccri["dates"]).to include("type" => "published", "value" => "2009-06-19")
      # summary keys never duplicated into the detail record
      expect(ccri.keys).not_to include("title", "doctype", "stage", "link", "yaml")
    end

    # Relations are a normalizer field that is NOT in COMPACT_KEYS, so the
    # generator routes them to the detail shards with no code of its own. This
    # pins that routing: the summary record must stay the seven compact keys.
    it "routes relations into the detail shard, never the summary record" do
      Dir.mktmpdir("relations-") do |repo|
        FileUtils.mkdir_p(File.join(repo, "data"))
        File.write(
          File.join(repo, "data", "iso-29862-2018.yaml"),
          "---\ndocidentifier:\n- content: ISO 29862:2018\n  primary: true\n" \
          "title:\n- content: Self adhesive tapes\n  language: en\n  type: main\n" \
          "relation:\n- type: obsoletes\n  bibitem:\n    docidentifier:\n" \
          "    - content: ISO 29862:2007\n      primary: true\n",
        )
        described_class.generate(File.join(repo, "data"),
                                 output: @out, generated: "2026-01-01")
        expect(detail_slots.first["relations"])
          .to eq([{ "type" => "obsoletes", "id" => "ISO 29862:2007" }])
        expect(summary_records.first.keys)
          .to contain_exactly("r", "c", "t", "s", "d", "u", "l")
      end
    end

    it "aligns positionally with the summary records" do
      generate
      expect(detail_slots.size).to eq(summary_records.size)
      summary_records.each_with_index do |rec, i|
        slot = detail_slots[i]
        expect(slot["r"]).to eq(rec["r"]) if slot
      end
    end

    # A title-only doc normalizes to the seven summary keys and nothing else, so
    # its detail record is empty. The slot must still be written, or every later
    # document's positional lookup would be off by one.
    it "writes a null slot for a document with no detail fields" do
      Dir.mktmpdir("nodetail-") do |repo|
        FileUtils.mkdir_p(File.join(repo, "data"))
        %w[a b c].each_with_index do |name, i|
          File.write(File.join(repo, "data", "#{name}.yaml"),
                     "---\ntitle:\n- content: Title only #{i}\n  language: en\n")
        end
        described_class.generate(File.join(repo, "data"),
                                 output: @out, generated: "2026-01-01",
                                 detail_shard_size: 5)
        expect(detail_slots).to eq([nil, nil, nil])
        expect(summary_records.size).to eq(3)
      end
    end

    it "shards independently of the summary shard size" do
      with_corpus(7, shard_size: 3, detail_shard_size: 2) do
        expect(shard_files("detail").size).to eq(4)
        expect(detail_slots.size).to eq(7)
      end
    end

    it "is suppressed by detail: false" do
      html = generate(detail: false)
      expect(shard_files("detail")).to be_empty
      expect(attr(html, "detail-shards")).to eq("0")
    end
  end

  context "an empty corpus" do
    it "writes a valid shell with no shards" do
      with_corpus(0) do |html|
        expect(attr(html, "total")).to eq("0")
        expect(attr(html, "shards")).to eq("0")
        expect(attr(html, "detail-shards")).to eq("0")
        expect(shard_files).to be_empty
        expect(html).to include('id="relaton-index-app"')
      end
    end
  end

  # --- streaming -----------------------------------------------------------

  # Asserting "the corpus is never materialized" by expecting some method NOT to
  # be called is worthless — it passes just as happily when that method no longer
  # exists. Observe the actual property instead: a completed shard must be on
  # disk while the corpus is still being read.
  it "flushes each shard as it fills, not after reading the whole corpus" do
    Dir.mktmpdir("stream-") do |repo|
      FileUtils.mkdir_p(File.join(repo, "data"))
      (1..6).each do |i|
        File.write(File.join(repo, "data", format("d%02d.yaml", i)),
                   "---\ndocidentifier:\n- content: DOC #{i}\n  primary: true\n")
      end

      gen = described_class.new(File.join(repo, "data"), output: @out,
                                            generated: "2026-01-01", shard_size: 2)
      shard0 = File.join(@out, "search-0000.json")
      written_early = false
      stream = gen.method(:each_document)

      allow(gen).to receive(:each_document) do |&block|
        index = 0
        stream.call do |item|
          index += 1
          # By the 5th document, docs 1-4 have filled two shards; the first must
          # already be on disk. A generator that buffered the corpus would not
          # have written anything yet.
          written_early = File.exist?(shard0) if index == 5
          block.call(item)
        end
      end

      gen.generate
      expect(written_early).to be true
    end
  end

  # --- output hygiene ------------------------------------------------------

  context "stale output" do
    it "removes shards left by a previous, larger build" do
      orphan_summary = File.join(@out, "search-0099.json")
      orphan_detail = File.join(@out, "detail-0099.json")
      legacy = File.join(@out, "search.json")
      [orphan_summary, orphan_detail, legacy].each { |f| File.write(f, "[]") }

      generate

      expect(File).not_to exist(orphan_summary)
      expect(File).not_to exist(orphan_detail)
      expect(File).not_to exist(legacy)
    end

    it "leaves them alone when overwrite is false" do
      orphan = File.join(@out, "search-0099.json")
      File.write(orphan, "[]")
      generate(overwrite: false)
      expect(File).to exist(orphan)
    end
  end

  # --- options -------------------------------------------------------------

  context "option validation" do
    it "rejects a non-positive shard size" do
      expect { described_class.generate(data_dir, output: @out, shard_size: 0) }
        .to raise_error(ArgumentError, /shard_size/)
    end

    it "rejects a non-positive detail shard size" do
      expect { described_class.generate(data_dir, output: @out, detail_shard_size: -1) }
        .to raise_error(ArgumentError, /detail_shard_size/)
    end

    it "no longer accepts a mode" do
      expect { described_class.generate(data_dir, output: @out, mode: "embedded") }
        .to raise_error(ArgumentError, /mode/)
    end
  end

  # --- branding (unchanged behaviour) --------------------------------------

  context "with a description" do
    let(:blurb) { "Welcome to the BIPM standards index site." }

    it "emits a meta description and carries it on the mount node" do
      html = generate(description: blurb)
      expect(html).to include(%(<meta name="description" content="#{blurb}">))
      expect(html).to include(%(data-description="#{blurb}"))
    end

    it "HTML-escapes the description" do
      html = generate(description: %(Tom & Jerry's "<b>index</b>"))
      expect(html).to include(
        %(<meta name="description" content="Tom &amp; Jerry&#39;s &quot;&lt;b&gt;index&lt;/b&gt;&quot;">),
      )
    end
  end

  context "with a favicon" do
    it "links an SVG favicon with its MIME type" do
      html = generate(favicon: "https://www.w3.org/assets/logos/w3c/w3c-no-bars.svg")
      expect(html).to include(
        %(<link rel="icon" href="https://www.w3.org/assets/logos/w3c/w3c-no-bars.svg" type="image/svg+xml">),
      )
    end

    it "derives the MIME type for other known extensions" do
      expect(generate(favicon: "favicon.png")).to include(%(type="image/png"))
      expect(generate(favicon: "favicon.ico")).to include(%(type="image/x-icon"))
    end

    it "ignores a query string when sniffing the type" do
      html = generate(favicon: "/assets/icon.svg?v=2")
      expect(html).to include(
        %(<link rel="icon" href="/assets/icon.svg?v=2" type="image/svg+xml">),
      )
    end

    it "omits the type for an unknown extension and passes the href through verbatim" do
      html = generate(favicon: "assets/icon")
      expect(html).to include(%(<link rel="icon" href="assets/icon">))
    end
  end

  context "without a description or favicon" do
    # A caller workflow forwarding an unset input passes "" — that must mean
    # "not set", not an empty meta/self-referencing icon href.
    [{}, { description: "", favicon: "" }, { description: "  ", favicon: "  " }].each do |opts|
      it "emits neither tag (#{opts.inspect})" do
        html = generate(opts)
        expect(html).not_to include('name="description"')
        expect(html).not_to include('rel="icon"')
        expect(html).not_to include("data-description")
      end
    end

    it "falls back to the default title when the title is blank" do
      described_class.generate(data_dir, output: @out, generated: "2026-01-01", title: "")
      html = File.read(File.join(@out, "index.html"), encoding: "utf-8")
      expect(html).to include("<title>Relaton Index</title>")
    end
  end

  context "when the frontend bundle is missing" do
    it "raises an actionable error" do
      Dir.mktmpdir do |empty|
        Relaton::Cli::FrontendAssets.with_dist_dir(empty) do
          expect { described_class.generate(data_dir, output: @out) }
            .to raise_error(Relaton::Cli::FrontendAssets::BuildMissingError, /rake build_frontend/)
        end
      end
    end
  end

  # --- corpus assembly (unchanged behaviour) -------------------------------

  context "with a sibling static/ folder" do
    let(:data_dir) { "spec/index_fixtures_static/data" }
    let(:base) { "https://raw.githubusercontent.com/relaton/relaton-data-nist/main" }

    def gen(opts = {})
      described_class.generate(
        data_dir,
        { output: @out, generated: "2026-01-01", base_url: base }.merge(opts),
      )
    end

    it "indexes the sibling static/ docs alongside the data docs by default" do
      gen
      # data/example.yaml (1) + static/nist + static/jcgm/100 (2); the duplicate
      # static/dup.yaml is de-duped away -> 3 documents total.
      expect(summary_records.size).to eq(3)
      expect(summary_records.map { |r| r["r"] }).to include("NIST Research Library (2022)")
    end

    it "builds a static doc's yaml link as base_url + static/<path>" do
      gen
      expect(summary_records.map { |r| r["u"] })
        .to include("#{base}/static/nist-research-library-2022.yaml")
    end

    it "indexes nested static docs" do
      gen
      expect(summary_records.map { |r| r["u"] })
        .to include("#{base}/static/jcgm/100-2008.yaml")
    end

    it "omits the static docs when static: false" do
      gen(static: false)
      expect(summary_records.size).to eq(1)
      expect(summary_records.map { |r| r["r"] }).not_to include("NIST Research Library (2022)")
    end

    it "de-dups an id present in both data/ and static/, letting data/ win" do
      gen
      urls = summary_records.map { |r| r["u"] }
      expect(urls).to include("#{base}/data/example.yaml")
      expect(urls.grep(/static\/dup\.yaml/)).to be_empty
    end
  end

  context "with docid-less (title-only) documents" do
    it "does not collapse distinct docs whose normalized id is blank" do
      Dir.mktmpdir("blankid-") do |repo|
        FileUtils.mkdir_p(File.join(repo, "data"))
        File.write(File.join(repo, "data", "a.yaml"),
                   "---\ntitle:\n- content: First title-only doc\n  language: en\n")
        File.write(File.join(repo, "data", "b.yaml"),
                   "---\ntitle:\n- content: Second title-only doc\n  language: en\n")
        described_class.generate(File.join(repo, "data"),
                                 output: @out, generated: "2026-01-01")
        titles = summary_records.map { |r| r["c"] }
        expect(titles).to contain_exactly("First title-only doc", "Second title-only doc")
      end
    end
  end
end
