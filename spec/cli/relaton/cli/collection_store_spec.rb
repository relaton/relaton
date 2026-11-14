require "relaton/cli/collection_store"
# `run_children`: `Process.spawn`, not `fork`, which Windows does not have.
require_relative "../../../relaton/support/child_processes"

# relaton#549: `relaton collection` keeps its collections in one lutaml-store
# FileSystem store under `<dir>/v2/`, and moves the flat files an older
# relaton wrote to `<dir>-v1.bak/` once.
RSpec.describe Relaton::Cli::CollectionStore do
  let(:dir) { "colls" }
  let(:fixture) { File.read "spec/fixtures/sample-collection.yaml" }
  let(:store) { described_class.new dir }

  def collection(title, docids = [])
    items = docids.map do |id|
      { "id" => id.delete(" "), "docidentifier" =>
        [{ "type" => "CC", "content" => id, "primary" => true }] }
    end
    Relaton::Bibcollection.new("title" => title, "items" => items)
  end

  def docids(coll)
    coll.items.map { |i| i.docidentifier.to_s }
  end

  # Every file under `<dir>/v2/` belongs to the store: its lock, a data file
  # per key, or that key's `.meta`. Nothing else.
  def expect_only_store_files
    base = File.join dir, described_class::LAYOUT
    files = Dir.glob("#{base}/**/*", File::FNM_DOTMATCH)
      .select { |f| File.file? f }
    data = files.select { |f| f.end_with? ".yaml" }
    meta = files.select { |f| f.end_with? ".meta" }
    expect(files - data - meta - ["#{base}/.lock"]).to eq []
    expect(data.size).to eq store.names.size
  end

  context "a flat file an older relaton wrote" do
    let(:mtime) { Time.utc(2020, 5, 6, 7, 8, 9) }

    before do
      FileUtils.mkdir_p dir
      File.write File.join(dir, "old.yaml"), fixture
      File.utime mtime, mtime, File.join(dir, "old.yaml")
      File.write File.join(dir, "notes.txt"), "not a collection"
      File.write File.join(dir, "list.yaml"), "- just a list\n"
    end

    it "is moved into the store and to the backup" do
      expect(store.names).to eq ["old.yaml"]
      expect(store.get("old.yaml").title).to eq "CalConnect Standards Registry"
      expect(store.updated("old.yaml")).to eq mtime
      expect(File.exist?(File.join(dir, "old.yaml"))).to be false
      expect(File.read("#{dir}-v1.bak/old.yaml")).to eq fixture
      expect_only_store_files
    end

    it "leaves a file that is no collection where it is" do
      store
      expect(File.read(File.join(dir, "notes.txt"))).to eq "not a collection"
      expect(File.exist?(File.join(dir, "list.yaml"))).to be true
    end

    it "is moved once: a second open changes nothing" do
      store
      expect { described_class.new dir }
        .not_to(change { Dir.glob("{#{dir},#{dir}-v1.bak}/**/*").sort })
    end

    it "does not replace a collection the store holds" do
      store.update("old.yaml") { collection("Newer") } # after the first move
      # An older relaton writes the flat file again.
      File.write File.join(dir, "old.yaml"), fixture.sub("CalConnect", "Again")
      reopened = nil
      expect { reopened = described_class.new dir }
        .to output(/`old.yaml` is in the store; the flat file is not imported, moved to .*old.yaml.1/)
        .to_stderr_from_any_process
      expect(reopened.get("old.yaml").title).to eq "Newer"
      expect(File.read("#{dir}-v1.bak/old.yaml")).to eq fixture
      expect(File.read("#{dir}-v1.bak/old.yaml.1")).to include "Again"
      expect(File.exist?(File.join(dir, "old.yaml"))).to be false
    end
  end

  it "warns once about a file that is not valid YAML, and leaves it" do
    FileUtils.mkdir_p dir
    File.write File.join(dir, "broken.yaml"), "root: [unclosed"
    expect { store }.to output(/`colls\/broken.yaml` isn't a collection/)
      .to_stderr_from_any_process
    expect(File.exist?(File.join(dir, "broken.yaml"))).to be true
  end

  it "puts the backup beside a directory named with a trailing slash" do
    FileUtils.mkdir_p dir
    File.write File.join(dir, "old.yaml"), fixture
    described_class.new "#{dir}/"
    expect(File.exist?("#{dir}-v1.bak/old.yaml")).to be true
  end

  it "moves each flat file once when processes open the store together" do
    FileUtils.mkdir_p dir
    5.times { |i| File.write File.join(dir, "c#{i}.yaml"), fixture }
    script = <<~RUBY
      require "relaton-cli"
      start_barrier!
      Relaton::Cli::CollectionStore.new #{File.expand_path(dir).inspect}
    RUBY
    statuses, logs = run_children Array.new(6) { script }
    expect(statuses).to all(be_success), logs.join("\n")
    expect(store.names).to eq %w[c0.yaml c1.yaml c2.yaml c3.yaml c4.yaml]
    expect(Dir.children("#{dir}-v1.bak").sort).to eq store.names
    expect(Dir.children(dir)).to eq [described_class::LAYOUT]
  end

  it "does not create a directory it only reads" do
    expect(store.names).to eq []
    expect(store.get("none.yaml")).to be_nil
    expect(Dir.exist?("#{dir}-v1.bak")).to be false
  end

  it "creates a collection once" do
    expect(store.create("a.yaml", collection("A"))).to be true
    expect(store.create("a.yaml", collection("B"))).to be false
    expect(store.get("a.yaml").title).to eq "A"
    expect(store.exist?("a.yaml")).to be true
    expect(store.updated("a.yaml")).to be_within(60).of(Time.now)
    expect_only_store_files
  end

  it "stores the collection YAML a reader of an older relaton reads" do
    store.create "a.yaml", collection("A", ["CC 1"])
    file = Dir.glob("#{dir}/#{described_class::LAYOUT}/**/*.yaml").first
    yaml = YAML.safe_load_file file
    expect(yaml["root"]["title"]).to eq "A"
    expect(yaml["root"]["items"].size).to eq 1
    expect(store.size("a.yaml")).to eq File.size(file)
  end

  it "updates a collection, and creates one that is missing" do
    store.update("a.yaml") { |c| c || collection("A") }
    store.update("a.yaml") { |c| c << collection("B", ["CC 2"]).items.first; c }
    expect(docids(store.get("a.yaml"))).to eq ["CC 2"]
  end

  it "lists the names that match a glob, sorted" do
    %w[b.yaml a.yaml c.yml].each { |n| store.create n, collection(n) }
    expect(store.names).to eq %w[a.yaml b.yaml c.yml]
    expect(store.names("*.yaml")).to eq %w[a.yaml b.yaml]
    expect(store.names("c.yml")).to eq %w[c.yml]
  end

  it "keeps the items of two processes that update one collection" do
    store.create "a.yaml", collection("A")
    scripts = ["CC 1", "CC 2"].map do |id|
      item = { "id" => id.delete(" "), "docidentifier" =>
               [{ "type" => "CC", "content" => id, "primary" => true }] }
      <<~RUBY
        require "relaton-cli"
        store = Relaton::Cli::CollectionStore.new #{File.expand_path(dir).inspect}
        start_barrier!
        store.update("a.yaml") do |c|
          # Without the lock, both processes would read before either
          # writes, and the second write would drop the first item.
          sleep 0.3
          c << #{item.inspect}
          c
        end
      RUBY
    end
    statuses, logs = run_children scripts
    expect(statuses).to all(be_success), logs.join("\n")
    expect(docids(store.get("a.yaml"))).to contain_exactly "CC 1", "CC 2"
  end

  context "source guard" do
    root = File.expand_path("../../../..", __dir__)
    io = /\b(?:File\.(?:write|binwrite|read|binread|open|new|delete|
             rename|exist\?|file\?|mtime|size|utime)|YAML\.load_file|
             FileUtils\.|Dir\.(?:glob|\[|children|exist\?|mkdir))/x

    def io_calls(path, io)
      method = nil
      File.readlines(path).each_with_index.filter_map do |line, i|
        next if line.strip.start_with? "#"

        method = Regexp.last_match(1) if line =~ /^\s*def (?:self\.)?(\w+[?!=]?)/
        [method, i + 1] if line.match? io
      end
    end

    it "does raw IO in the store only to move the flat files" do
      calls = io_calls File.join(root, "lib/relaton/cli/collection_store.rb"), io
      allowed = %w[move_flat_files flat_collections backup]
      expect(calls.reject { |m, _| allowed.include? m }).to eq []
    end

    it "reads and writes no collection file in the CLI" do
      calls = io_calls(
        File.join(root, "lib/relaton/cli/subcommand_collection.rb"), io
      )
      # `import` reads its XML file (user input); `export` writes its XML
      # file and `get -o` the item (user output).
      allowed = %w[read_xml export output_item]
      expect(calls.reject { |m, _| allowed.include? m }).to eq []
    end

    it "layers no lock of its own over the store" do
      code = File.read File.join(root, "lib/relaton/cli/collection_store.rb")
      expect(code).not_to match(/\b(?:Mutex|Monitor|flock|LOCK_EX)\b/)
    end
  end
end
