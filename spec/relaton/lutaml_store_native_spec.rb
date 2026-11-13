require "fileutils"
require "relaton/db"

# relaton#548: the Db cache has one storage layer, lutaml-store. Every row
# and document goes through the two FileSystem stores under `<dir>/v2/`, and
# no parallel IO layer writes beside them. See "lutaml-store audit" in
# docs/db.md.
RSpec.describe "Relaton::Db::Cache on lutaml-store" do
  let(:dir) { "nativecache" }
  let(:cache) { Relaton::Db::Cache.new dir }
  let(:xml) do
    <<~XML
      <bibdata><fetched>#{Date.today}</fetched><docidentifier type="ISO" primary="true">ISO 19115-1:2014</docidentifier></bibdata>
    XML
  end

  def pubid(ref)
    require "pubid"
    Pubid::Iso::Identifier.parse ref
  end

  def store(name)
    cache.instance_variable_get(:"@#{name}")
  end

  before { FileUtils.rm_rf [dir, "#{dir}-v1.bak"] }
  after { FileUtils.rm_rf [dir, "#{dir}-v1.bak"] }

  # Every file under `<dir>/v2/` belongs to a store: its lock, an entry's
  # data file (one per store key), or that entry's `.meta`. Nothing else.
  def expect_only_store_files # rubocop:disable Metrics/AbcSize
    base = File.join(dir, Relaton::Db::Cache::LAYOUT)
    top = Dir.children(base).sort
    expect(top).to eq(%w[docs rows] & top)
    { "rows" => ".json", "docs" => ".xml" }.each do |name, ext|
      files = Dir.glob("#{base}/#{name}/**/*", File::FNM_DOTMATCH)
        .select { |f| File.file? f }
      data = files.select { |f| f.end_with? ext }
      meta = files.select { |f| f.end_with? ".meta" }
      others = files - data - meta - ["#{base}/#{name}/.lock"]
      expect(others).to eq []
      expect(data.size).to eq store(name).keys.size
      expect(meta.map { |f| f.delete_suffix ".meta" })
        .to all(satisfy { |f| data.include? "#{f}#{ext}" })
    end
  end

  it "keeps every file it writes visible to the stores" do # rubocop:disable RSpec/MultipleExpectations,RSpec/ExampleLength
    cache.store pubid("ISO 19115-1"), xml, item_key: pubid("ISO 19115-1:2014")
    cache[pubid("ISO 9999")] = "not_found #{Date.today}"
    cache[pubid("ISO 19115-2:2019")] = xml.sub("19115-1:2014", "19115-2:2019")
    expect_only_store_files

    cache.delete pubid("ISO 19115-2:2019")
    cache.expire pubid("ISO 9999"), nil
    expect_only_store_files

    processor = Relaton::Db::Registry.instance[:relaton_iso]
    allow(processor).to receive(:grammar_hash).and_return "changed"
    Relaton::Db::Cache.new dir
    expect_only_store_files

    cache.clear
    expect_only_store_files
  end

  context "the old-layout import (relaton#240)" do
    before do
      FileUtils.mkdir_p "#{dir}/iso"
      File.write "#{dir}/iso/iso_123.xml", xml.sub("ISO 19115-1:2014", "ISO 123")
    end

    it "keeps its marker in the rows store, not in a file" do
      expect(cache[pubid("ISO 123")]).to include "ISO 123"
      expect(File.exist?("#{dir}/v2/.v1-imported")).to be false
      expect(store(:rows).get(Relaton::Db::Cache::V1_IMPORTED_KEY)).not_to be_nil
      expect_only_store_files
    end

    it "does not import again after a clear" do
      cache.clear
      expect(store(:rows).get(Relaton::Db::Cache::V1_IMPORTED_KEY)).not_to be_nil
      expect(Relaton::Db::Cache.new(dir)[pubid("ISO 123")]).to be_nil
    end

    it "never deletes the marker while it clears" do
      cache # import
      rows = store(:rows)
      allow(rows).to receive(:delete).and_wrap_original do |m, key|
        expect(key).not_to eq Relaton::Db::Cache::V1_IMPORTED_KEY
        m.call key
      end
      cache.clear
    end

    it "still reads the marker file an older relaton wrote" do
      FileUtils.mkdir_p "#{dir}/v2"
      File.write "#{dir}/v2/.v1-imported", ""
      expect(cache[pubid("ISO 123")]).to be_nil
    end

    it "does not list the marker as a row" do
      expect(cache.rows).to all(be_a(Hash))
    end
  end

  it "clears rows and documents under one rows transaction" do
    cache[pubid("ISO 19115-1:2014")] = xml
    rows = store(:rows).adapter
    in_transaction = false
    allow(rows).to receive(:transaction).and_wrap_original do |m, &block|
      m.call do
        in_transaction = true
        block.call
      ensure
        in_transaction = false
      end
    end
    allow(store(:docs)).to receive(:clear).and_wrap_original do |m|
      expect(in_transaction).to be true
      m.call
    end
    cache.clear
    expect(store(:docs)).to have_received(:clear)
  end

  context "source guard" do
    root = File.expand_path("../..", __dir__)
    sources = Dir[File.join(root, "lib/relaton/db{,/*}.rb")]
    rel = ->(path) { path.delete_prefix("#{root}/") }
    io = /\b(?:File\.(?:write|binwrite|read|binread|readlines|foreach|open|
             new|delete|unlink|rename|truncate|exist\?|touch)|IO\.|
             FileUtils\.|Pathname|Tempfile|
             Dir\.(?:glob|\[|children|entries|mkdir|rmdir|delete|exist\?))/x
    content_write = /\b(?:File\.(?:write|binwrite|open|new)|IO\.|
                       FileUtils\.touch)/x
    # The whole-directory operations (a stale file at the cache path, `mv`,
    # `flush_caches`) and the one-shot v1 migration. No row or document.
    allowed = {
      "lib/relaton/db.rb" => %w[flush_caches],
      "lib/relaton/db/cache.rb" =>
        %w[initialize mv archive_old_layout import_old_layout v1_imported?],
    }

    # [path, method, line] of every raw IO call outside a comment.
    calls = sources.flat_map do |path|
      method = nil
      File.readlines(path).each_with_index.filter_map do |line, i|
        next if line.strip.start_with? "#"

        method = Regexp.last_match(1) if line =~ /^\s*def (?:self\.)?(\w+[?!=]?)/
        [rel[path], method, i + 1, line] if line.match? io
      end
    end

    it "finds the Db sources and their sanctioned IO" do
      expect(sources.map(&rel)).to include("lib/relaton/db.rb", "lib/relaton/db/cache.rb")
      expect(calls).not_to be_empty
    end

    it "does raw IO only in the sanctioned methods" do
      offenders = calls.reject { |path, m, _, _| allowed.fetch(path, []).include? m }
      expect(offenders.map { |p, m, n, _| "#{p}:#{n} (#{m})" }).to eq []
    end

    it "writes no file content beside the stores" do
      offenders = calls.select { |_, _, _, line| line.match? content_write }
      expect(offenders.map { |p, m, n, _| "#{p}:#{n} (#{m})" }).to eq []
    end

    it "layers no lock of its own over the stores" do
      code = File.readlines(File.join(root, "lib/relaton/db/cache.rb"))
        .reject { |line| line.strip.start_with? "#" }.join
      expect(code).not_to match(/\b(?:Mutex|Monitor|flock|LOCK_EX)\b/)
    end
  end
end
