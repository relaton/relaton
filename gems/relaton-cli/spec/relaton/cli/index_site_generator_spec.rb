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
      { output: @out, title: "BIPM Index", generated: "2026-01-01", machine_index: false,
        base_url: "https://raw.githubusercontent.com/relaton/relaton-data-bipm/v2" }.merge(opts),
    )
    File.read(File.join(@out, "index.html"), encoding: "utf-8")
  end


  # --- machine index (contract v2: manifest + shards + monolith) ----------

  def manifest
    JSON.parse(File.read(File.join(@out, "index", "manifest.json")))
  end

  def machine_shards
    Dir[File.join(@out, "index", "shard-*.json")].sort
  end

  def all_machine_records
    machine_shards.flat_map { |f| JSON.parse(File.read(f)) }
  end

  # Writes `rows` as the repo's committed index-vN.yaml — the file the
  # generator falls back to for a docid it cannot parse from the document.
  def write_committed_index(repo, rows, name: "index-v2")
    File.write(File.join(repo, "#{name}.yaml"), rows.to_yaml)
  end

  def with_pubid_corpus(count, opts = {})
    Dir.mktmpdir("pubid-corpus-") do |repo|
      FileUtils.mkdir_p(File.join(repo, "data"))
      (1..count).each do |i|
        content = <<~YAML
          ---
          docidentifier:
          - content: ISO #{1000 + i}#{i.positive? && i % 3 == 1 ? "-1:2014" : ""}
            primary: true
          title:
          - content: Standard #{i}
            type: main
        YAML
        File.write(File.join(repo, "data", format("iso-%03d.yaml", i)), content)
      end
      yield described_class.generate(
        File.join(repo, "data"),
        { output: @out, generated: "2026-01-01" }.merge(opts),
      )
    end
  end

  it "emits a contract-v2 manifest" do
    with_pubid_corpus(3, flavor: "iso") do
      expect(manifest).to include(
        "version" => 2, "index" => "index-v2", "key" => "root-number",
        "algorithm" => "crc32", "shards" => 0, "count" => 3,
        "generated" => "2026-01-01",
      )
    end
  end

  it "does not shard a corpus below MIN_ROWS" do
    with_pubid_corpus(3, flavor: "iso") do
      expect(manifest["shards"]).to eq(0)
      expect(machine_shards).to be_empty
      expect(File).to exist(File.join(@out, "index-v2.yaml"))
      expect(File).to exist(File.join(@out, "index-v2.zip"))
    end
  end

  it "refuses to build a machine index without a pubid flavor" do
    expect { generate(machine_index: true) }
      .to raise_error(ArgumentError, /pubid-flavor/)
  end

  describe "sharding" do
    before { stub_const("Relaton::Cli::IndexSiteGenerator::MachineIndex::MIN_ROWS", 10) }

    it "puts every document in exactly one shard, at crc32(root number) % N" do
      with_pubid_corpus(40, flavor: "iso") do
        m = manifest
        expect(m["shards"]).to eq(16) # next_pow2(40/15)=4, clamped to MIN_SHARDS=16
        records = all_machine_records
        expect(records.size).to eq(40)

        records.each do |rec|
          key = Pubid::Iso::Identifier.parse(rec["r"]).root.number.to_s
          shard = format("shard-%05d.json", Zlib.crc32(key) % m["shards"])
          rows = JSON.parse(File.read(File.join(@out, "index", shard)))
          expect(rows).to include(rec)
          expect(rec["id"]).to include("_type")
          expect(rec["file"]).to start_with("data/")
        end
      end
    end

    it "writes no empty shards" do
      with_pubid_corpus(3, flavor: "iso") do
        machine_shards.each do |f|
          expect(JSON.parse(File.read(f))).not_to be_empty
        end
      end
    end
  end

  describe "structured corpora (flavor: iso)" do
    before { stub_const("Relaton::Cli::IndexSiteGenerator::MachineIndex::MIN_ROWS", 10) }

    it "names the index from the flavor's INDEXFILE" do
      with_pubid_corpus(30, flavor: "iso") do
        expect(manifest).to include("index" => Relaton::Iso::INDEXFILE,
                                    "key" => "root-number")
        expect(manifest["count"]).to eq(30)
        expect(File).to exist(File.join(@out, "index-v2.yaml"))
        expect(Dir[File.join(@out, "index-v3.yaml")]).to be_empty
        expect(Dir[File.join(@out, "index-v1.yaml")]).to be_empty
      end
    end

    it "maps a pubid flavor whose relaton namespace differs (3gpp -> ThreeGpp)" do
      with_pubid_corpus(3, flavor: "3gpp") do
        expect(manifest["index"]).to eq(Relaton::ThreeGpp::INDEXFILE)
      end
    end

    it "lets index_name override the derived name" do
      with_pubid_corpus(3, flavor: "iso", index_name: "index-v9") do
        expect(manifest["index"]).to eq("index-v9")
        expect(File).to exist(File.join(@out, "index-v9.yaml"))
        expect(File).to exist(File.join(@out, "index-v9.zip"))
      end
    end

    it "raises for a flavor no relaton namespace carries" do
      expect { described_class.generate(data_dir, output: @out, flavor: "nosuchflavor") }
        .to raise_error(ArgumentError, /nosuchflavor/)
    end

    # Resolving the flavor runs its autoload. A NameError from inside that
    # file is a real bug and must not be relabelled "unknown flavor".
    it "lets a NameError from inside the flavor surface as itself" do
      allow(::Relaton).to receive(:const_get).and_call_original
      allow(::Relaton).to receive(:const_get).with("Iso")
        .and_raise(NameError.new("uninitialized constant Relaton::Iso::Typo", :Typo))
      expect { described_class.generate(data_dir, output: @out, flavor: "iso") }
        .to raise_error(NameError, /Typo/)
    end

    it "rejects an index name that is not a single file name" do
      # A blank name is not in this list: like --favicon "", it means "not set".
      ["../escape", "sub/dir", ".hidden", "a b"].each do |name|
        expect do
          described_class.generate(data_dir, output: @out, flavor: "iso", index_name: name)
        end.to raise_error(ArgumentError, /single file name/), "accepted #{name.inspect}"
      end
    end

    it "purges the previous build's monolith even under a custom name" do
      with_pubid_corpus(3, flavor: "iso", index_name: "custom-index") do
        expect(File).to exist(File.join(@out, "custom-index.zip"))
      end
      with_pubid_corpus(3, flavor: "iso") do
        expect(File).not_to exist(File.join(@out, "custom-index.yaml"))
        expect(File).not_to exist(File.join(@out, "custom-index.zip"))
        expect(File).to exist(File.join(@out, "index-v2.yaml"))
      end
    end

    it "carries the same id in the shard and in the monolith" do
      stub_const("Relaton::Cli::IndexSiteGenerator::MachineIndex::MIN_ROWS", 1)
      with_pubid_corpus(6, flavor: "iso") do
        monolith = YAML.safe_load(File.read(File.join(@out, "index-v2.yaml")),
                                  permitted_classes: [Symbol])
        by_file = monolith.to_h { |row| [row[:file], row[:id]] }
        expect(all_machine_records).to all(satisfy { |rec| rec["id"] == by_file[rec["file"]] })
      end
    end

    it "keeps a document family in one shard and carries structured ids" do
      stub_const("Relaton::Cli::IndexSiteGenerator::MachineIndex::MIN_ROWS", 1)
      Dir.mktmpdir("family-") do |repo|
        FileUtils.mkdir_p(File.join(repo, "data"))
        family = [
          "ISO 19115", "ISO 19115-1:2014", "ISO 19115-1:2014/Amd 1:2018",
          "ISO 19116", # different family
        ]
        family.each_with_index do |id, i|
          File.write(File.join(repo, "data", format("f-%02d.yaml", i)),
            "---\ndocidentifier:\n- content: #{id}\n  primary: true\n")
        end
        described_class.generate(File.join(repo, "data"),
          output: @out, generated: "2026-01-01", flavor: "iso")

        m = manifest
        records = all_machine_records
        expect(records.size).to eq(4)
        expect(records).to all(include("id" => hash_including("_type")))

        family_recs = records.select { |r| r["r"].start_with?("ISO 19115") }
        other = records.find { |r| r["r"] == "ISO 19116" }
        family_shards = family_recs.map do |rec|
          machine_shards.find { |f| JSON.parse(File.read(f)).any? { |row| row["r"] == rec["r"] } }
        end
        other_shard = machine_shards.find { |f| JSON.parse(File.read(f)).any? { |row| row["r"] == other["r"] } }
        expect(family_shards.uniq.size).to eq(1) # whole family together
        expect(other_shard).not_to eq(family_shards.first) # different number apart
      end
    end

    # The generator parses each document's *rendered* docid, while the
    # committed index was built by the flavor's DataFetcher from source
    # metadata. Five shipping corpora disagree on a handful of rows (ieee 69,
    # itu-r 47, iec 42, itu 3, nist 3), so the committed row is the authority.
    describe "a docid the pubid parser rejects" do
      def with_unparseable(committed_rows)
        stub_const("Relaton::Cli::IndexSiteGenerator::MachineIndex::MIN_ROWS", 1)
        Dir.mktmpdir("nofam-") do |repo|
          FileUtils.mkdir_p(File.join(repo, "data"))
          ["ISO 9999", "not a standards identifier"].each_with_index do |id, i|
            File.write(File.join(repo, "data", format("n-%02d.yaml", i)),
              "---\ndocidentifier:\n- content: #{id}\n  primary: true\n")
          end
          write_committed_index(repo, committed_rows) if committed_rows
          described_class.generate(File.join(repo, "data"),
            output: @out, generated: "2026-01-01", flavor: "iso")
          yield
        end
      end

      it "takes its id from the committed index" do
        hash = Pubid::Iso::Identifier.parse("ISO 8888").to_hash
        with_unparseable([{ id: hash, file: "data/n-01.yaml" }]) do
          rec = all_machine_records.find { |r| r["r"] == "not a standards identifier" }
          expect(rec).not_to be_nil
          expect(rec["id"]).to eq(hash)
          shard = format("shard-%05d.json", Zlib.crc32("8888") % manifest["shards"])
          expect(JSON.parse(File.read(File.join(@out, "index", shard)))).to include(rec)
        end
      end

      # A legacy index published under the same name carries plain strings. One
      # of those in a row would break both the monolith (yaml_nested walks a
      # Hash) and the consumer (FileIO#deserialize_id calls from_hash).
      it "ignores a committed row whose id is a plain string" do
        expect(Relaton.logger_pool).to receive(:warn).with(/skipped 1 of 2/, "relaton-cli")
        with_unparseable([{ id: "CC/A 0001:2000", file: "data/n-01.yaml" }]) do
          expect(all_machine_records.map { |r| r["r"] }).to eq(["ISO 9999"])
        end
      end

      it "is dropped and reported when the committed index has no row for it" do
        # Util.warn reaches the logger through Bib::Util#method_missing, so the
        # pool is the only interceptable point.
        expect(Relaton.logger_pool).to receive(:warn).with(/skipped 1 of 2/, "relaton-cli")
        with_unparseable(nil) do
          expect(all_machine_records.map { |r| r["r"] }).to eq(["ISO 9999"])
          expect(manifest["count"]).to eq(1)
        end
      end
    end

    it "writes a monolith that round-trips through the pubid class" do
      with_pubid_corpus(5, flavor: "iso") do
        rows = YAML.safe_load(File.read(File.join(@out, "index-v2.yaml")),
                              permitted_classes: [Symbol], aliases: true)
        expect(rows.size).to eq(5)
        parsed = rows.map { |r| Pubid::Iso::Identifier.from_hash(r[:id]) }
        expect(parsed).to all(be_a(Pubid::Iso::Identifier))
        expect(File).to exist(File.join(@out, "index-v2.zip"))
      end
    end

    # `copublishers` is an Array in the pubid hash. Quoted into a String it
    # cannot be cast back, and FileIO rejects the whole index on that one row.
    it "round-trips copublished ids, whose hash carries an Array" do
      Dir.mktmpdir("copub-") do |repo|
        FileUtils.mkdir_p(File.join(repo, "data"))
        refs = ["ISO/IEC 27001:2022", "ISO/IEC/IEEE 8802-3:2021",
                "ISO/IEC DIR 2 IEC SUP:2010"]
        refs.each_with_index do |ref, i|
          File.write(File.join(repo, "data", format("c-%02d.yaml", i)),
                     "---\ndocidentifier:\n- content: #{ref}\n  primary: true\n")
        end
        described_class.generate(File.join(repo, "data"),
                                 output: @out, generated: "2026-01-01", flavor: "iso")

        rows = YAML.safe_load(File.read(File.join(@out, "index-v2.yaml")),
                              permitted_classes: [Symbol])
        by_ref = rows.to_h { |r| [Pubid::Iso::Identifier.from_hash(r[:id]).to_s, r[:id]] }
        expect(by_ref.keys).to match_array(refs)
        refs.each do |ref|
          expect(by_ref[ref]).to eq(Pubid::Iso::Identifier.parse(ref).to_hash)
        end
      end
    end
  end

  it "keeps machine rows repo-relative even when --base-url is set" do
    with_pubid_corpus(3, flavor: "iso",
                      base_url: "https://relaton.github.io/relaton-data-x") do
      all_machine_records.each do |rec|
        expect(rec["file"]).to start_with("data/")
        expect(rec["file"]).not_to include("http")
      end
    end
  end

  it "can be disabled with machine_index: false" do
    generate(machine_index: false)

    expect(File).not_to exist(File.join(@out, "index", "manifest.json"))
    expect(machine_shards).to be_empty
    expect(Dir[File.join(@out, "index-v*.yaml")]).to be_empty
  end

  it "builds the human site without a pubid flavor when the machine index is off" do
    expect { generate(machine_index: false) }.not_to raise_error
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
        { output: @out, generated: "2026-01-01", machine_index: false }.merge(opts),
      )
      yield File.read(File.join(@out, "index.html"), encoding: "utf-8")
    end
  end

  it "returns the path to index.html" do
    path = described_class.generate(data_dir, output: @out, generated: "2026-01-01",
                                    machine_index: false)
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
                                 output: @out, generated: "2026-01-01",
                                 machine_index: false)
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
                                 detail_shard_size: 5, machine_index: false)
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

      gen = described_class.new(File.join(repo, "data"), output: @out, machine_index: false,
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
      described_class.generate(data_dir, output: @out, generated: "2026-01-01",
                               title: "", machine_index: false)
      html = File.read(File.join(@out, "index.html"), encoding: "utf-8")
      expect(html).to include("<title>Relaton Index</title>")
    end
  end

  context "when the frontend bundle is missing" do
    it "raises an actionable error" do
      Dir.mktmpdir do |empty|
        Relaton::Cli::FrontendAssets.with_dist_dir(empty) do
          expect { described_class.generate(data_dir, output: @out, machine_index: false) }
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
        { output: @out, generated: "2026-01-01", base_url: base,
          machine_index: false }.merge(opts),
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
                                 output: @out, generated: "2026-01-01",
                                 machine_index: false)
        titles = summary_records.map { |r| r["c"] }
        expect(titles).to contain_exactly("First title-only doc", "Second title-only doc")
      end
    end
  end

  # --- MachineIndex unit specs -------------------------------------------
  #
  # Driven directly with an injected parser rather than through `generate`.
  # The examples above use the real `Pubid::Iso::Identifier` via `flavor:`, and
  # ISO has no id that parses yet yields no root number, so the numberless path
  # is unreachable from there. `MachineIndex.new(pubid_class:)` is public, so no
  # production seam is needed.
  describe Relaton::Cli::IndexSiteGenerator::MachineIndex do
    # Minimal stand-in for a pubid identifier. `number: nil` models a flavor
    # whose ids are *named* rather than numbered.
    FakeRoot = Struct.new(:number)
    FakeId = Struct.new(:num, :rendered) do
      def root = FakeRoot.new(num)
      def to_hash = { "_type" => "fake", "number" => num.to_s }
    end

    # Parses everything; ids starting with "name-" carry no root number.
    class NumberlessParser
      def self.parse(rendered)
        FakeId.new(rendered.start_with?("name-") ? nil : rendered[/\d+/], rendered)
      end

      def self.from_hash(hash) = FakeId.new(hash["number"], nil)
    end

    # RFCs parse; "draft-" ids do not parse at all.
    class PartialParser
      def self.parse(rendered)
        raise ArgumentError, "unparseable" if rendered.start_with?("draft-")

        FakeId.new(rendered[/\d+/], rendered)
      end

      def self.from_hash(hash) = FakeId.new(hash["number"], nil)
    end

    def build(parser, ids, committed: nil)
      described_class.new(pubid_class: parser, index_name: "index-v2",
                          committed: committed).tap do |mi|
        ids.each_with_index { |id, i| mi.add(id, format("data/d%04d.yaml", i)) }
      end
    end

    def shard_sizes(machine)
      machine.each_shard.to_a.map { |(_, rows)| rows.size }
    end

    # The key is `crc32(root.number.to_s) % N`, the same expression
    # Relaton::Index bsearches on. A rendered-id fallback would break that
    # identity: a client computing the key from its parsed query would look in
    # a bucket the row is not in, and read the miss as not-found.
    describe "rows whose id parses but has no root number" do
      it "keys on the empty string" do
        machine = build(NumberlessParser, ["name-alpha", "STD 7"])
        expect(machine.rows.map(&:key)).to contain_exactly("", "7")
      end

      it "puts a wholly numberless corpus in shard 0" do
        stub_const("#{described_class}::MIN_ROWS", 10)
        machine = build(NumberlessParser, (1..400).map { |i| "name-#{i}" })

        shards = machine.each_shard.to_a
        expect(shards.size).to eq(1)
        expect(shards.first[0]).to eq(format("%05d", Zlib.crc32("") % machine.shard_count))
        expect(shards.first[1].size).to eq(400)
      end
    end

    describe "#key_strategy" do
      it "is always root-number" do
        expect(build(PartialParser, ["RFC 1"]).key_strategy).to eq("root-number")
      end
    end

    describe "#monolith_filename" do
      it "is the index name with a .yaml extension" do
        expect(build(PartialParser, []).monolith_filename).to eq("index-v2.yaml")
      end
    end

    describe "#row_record" do
      it "always carries the structured id" do
        row = build(PartialParser, ["RFC 7"]).rows.first
        expect(build(PartialParser, []).row_record(row))
          .to eq("r" => "RFC 7", "file" => "data/d0000.yaml",
                 "id" => { "_type" => "fake", "number" => "7" })
      end
    end

    describe "an index with unparseable rows" do
      let(:machine) do
        stub_const("#{described_class}::MIN_ROWS", 10)
        build(PartialParser, (1..96).map { |i| "RFC #{i}" } +
                             (1..4).map { |i| "draft-thing-#{i}" })
      end

      it "takes an unparseable row's id from the committed index" do
        committed = { "data/d0001.yaml" => { "_type" => "fake", "number" => "42" } }
        rescued = build(PartialParser, ["RFC 1", "draft-x"], committed: committed)
        expect(rescued.skipped_count).to eq(0)
        expect(rescued.rows.last.id_hash).to eq(committed["data/d0001.yaml"])
        expect(rescued.rows.last.key).to eq("42")
      end

      it "excludes the unparseable rows, and reports how many" do
        expect(machine.count).to eq(100)
        expect(machine.indexed_rows.size).to eq(96)
        expect(machine.skipped_count).to eq(4)
        expect(machine.indexed_rows.map(&:rendered)).to all(start_with("RFC"))
      end

      it "writes a monolith whose every row is a structured id" do
        Dir.mktmpdir("mono-") do |dir|
          path = File.join(dir, "index-v3.yaml")
          machine.write_monolith(path)
          rows = YAML.safe_load(File.read(path), permitted_classes: [Symbol])
          # A single plain-string row would make FileIO#deserialize_id raise
          # InvalidIndexError and reject the whole index.
          expect(rows.size).to eq(96)
          expect(rows.map { |r| r[:id] }).to all(be_a(Hash))
        end
      end

      it "counts only the written rows in the manifest" do
        m = machine.manifest(generated: "2026-01-01")
        expect(m["count"]).to eq(96)
        expect(m["index"]).to eq("index-v2")
        expect(m["key"]).to eq("root-number")
      end
    end

    describe "Row" do
      it "does not retain the identifier object" do
        # Holding it costs 3.14 KB/row against 0.44 KB for the derived values
        # alone — 543 MB vs 76 MB on a 177k-row corpus.
        expect(described_class::Row.members).to eq(%i[rendered file key id_hash])
      end
    end

    describe "#yaml_nested" do
      it "round-trips arrays of hostile, typed and nested values" do
        hash = {
          "_type" => "fake",
          "copublishers" => ["IEC", "yes", "a: b", "#x", "é", " ", "~", "\#{", nil, true, 3],
          "base" => { "_type" => "fake", "list" => [{ "_type" => "k", "n" => "1" }], "empty" => [] },
        }
        machine = described_class.new(pubid_class: PartialParser, index_name: "index-v2")
        buf = +"---\n- :id:\n"
        machine.yaml_nested(buf, hash, "    ")
        buf << "  :file: data/x.yaml\n"
        expect(YAML.safe_load(buf, permitted_classes: [Symbol]).first[:id]).to eq(hash)
      end
    end

    describe "#yaml_scalar" do
      # Property: whatever goes in must come back out byte-identical after a
      # YAML round trip. Catches type coercion, whitespace loss and, most
      # importantly, control characters that make the whole file unparseable.
      [
        "ISO 9999", "data/x.yaml", "ISO/IEC 1:2 3",
        "yes", "no", "on", "off", "true", "false", "null", "~", "y", "N",
        "trailing ", " leading", "a\tb", "\e[1m", "", "42", "-x", "a: b", "a #c",
        # A pubid to_hash carries real booleans and numbers (CIE's d_prefix,
        # 31 of its 1139 rows). Stringifying one makes the published row differ
        # from the repo's own index for that document.
        true, false, nil, 42
      ].each do |value|
        it "round-trips #{value.inspect}" do
          machine = described_class.new(pubid_class: PartialParser, index_name: "index-v2")
          doc = "---\n- :id: #{machine.yaml_scalar(value)}\n  :file: data/x.yaml\n"
          parsed = YAML.safe_load(doc, permitted_classes: [Symbol])
          expect(parsed.first[:id]).to eq(value)
        end
      end
    end
  end

end
