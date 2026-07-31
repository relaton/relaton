require "tmpdir"
require "fileutils"

RSpec.describe Relaton::Ieee::DataFetcher do
  describe ".build_index" do
    around do |example|
      Dir.mktmpdir("ieee-build-index") do |tmp|
        @tmp = tmp
        FileUtils.mkdir_p File.join(tmp, "data")
        Dir.chdir(tmp) { example.run }
      end
    end

    # build_index calls find_or_create(:ieee, file:, pubid_class:), which
    # overwrites the pooled read index; save and restore it so other suites'
    # examples keep the injected index-v2 fixture.
    before { @saved = Relaton::Index.pool.instance_variable_get(:@pool)[:IEEE] }
    after  { Relaton::Index.pool.instance_variable_get(:@pool)[:IEEE] = @saved }

    def write_doc(name, content)
      doc = { "docidentifier" => [{ "content" => content, "type" => "IEEE", "primary" => true }] }
      File.write File.join("data", name), doc.to_yaml
    end

    it "indexes parseable ids as pubid `_type` rows and skips unparseable ones" do
      write_doc "ieee-std-528-2019.yaml", "IEEE Std 528-2019"
      write_doc "ieee-std-1619-2007.yaml", "IEEE Std 1619-2007"
      write_doc "a-call.yaml", "A Call" # free-text title junk pubid can't parse

      result = nil
      expect do
        result = described_class.build_index(dir: "data", index_file: "index-v2.yaml")
      end.to output(%r{index-v2\.yaml: 2/3 indexed, 1 skipped \(66\.7% coverage\)})
        .to_stderr_from_any_process

      expect(result).to eq(total: 3, indexed: 2, skipped: 1)

      rows = YAML.safe_load(File.read("index-v2.yaml"), permitted_classes: [Symbol])
      expect(rows.size).to eq 2
      expect(rows.map { |r| r[:id]["_type"] })
        .to all(start_with("pubid:ieee:"))
      expect(rows.map { |r| r[:file] })
        .to contain_exactly("data/ieee-std-528-2019.yaml", "data/ieee-std-1619-2007.yaml")
    end
  end
end
