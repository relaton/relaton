require "zlib"
require "json"

describe Relaton::Index::ShardSource do
  subject(:source) { described_class.new("iso", pages, TestIdentifier) }

  let(:pages) { "https://relaton.github.io/relaton-data-iso/" }
  let(:manifest_url) { "#{pages}index/manifest.json" }
  let(:shards) { 16 }
  let(:manifest) do
    { "version" => 2, "index" => "index-v2", "count" => 3, "shards" => shards,
      "key" => "root-number", "algorithm" => "crc32", "generated" => "2026-09-23" }
  end

  let(:id1) { TestIdentifier.create(publisher: "ISO", number: 1) }
  let(:id2) { TestIdentifier.create(publisher: "ISO", number: 2) }

  def shard_url(number)
    format("%<pages>sindex/shard-%<n>05d.json",
           pages: pages, n: Zlib.crc32(number.to_s) % shards)
  end

  def row(id, file)
    { "r" => id.to_s, "file" => file, "id" => id.to_hash }
  end

  def zipped(rows)
    yaml = rows.map { |r| { id: r[:id].to_hash, file: r[:file] } }.to_yaml
    Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry "index-v2.yaml"
      zip.write yaml
    end.string
  end

  before do
    Relaton::Index.instance_variable_set(:@config, nil)
    stub_request(:get, manifest_url).to_return(status: 200, body: manifest.to_json)
  end

  describe "#rows" do
    context "when the shard of the id exists" do
      before do
        stub_request(:get, shard_url(1))
          .to_return(status: 200, body: [row(id1, "data/1.yaml")].to_json)
      end

      it "returns the deserialized rows of that shard" do
        expect(source.rows(id1)).to eq [{ id: id1, file: "data/1.yaml" }]
      end

      it "names the shard crc32(root.number) % shards, five digits" do
        source.rows(id1)
        expect(a_request(:get, %r{/index/shard-\d{5}\.json\z})).to have_been_made.once
        expect(a_request(:get, shard_url(1))).to have_been_made.once
      end

      it "does not fetch the whole index" do
        source.rows(id1)
        expect(a_request(:get, /\.zip\z/)).not_to have_been_made
      end

      it "keys a supplement on its root document number" do
        amd = TestIdentifier.create(publisher: "ISO", number: 99)
        amd.root = id1
        source.rows(amd)
        expect(a_request(:get, shard_url(1))).to have_been_made.once
      end

      it "keeps the manifest and the shard in memory" do
        2.times { source.rows(id1) }
        expect(a_request(:get, manifest_url)).to have_been_made.once
        expect(a_request(:get, shard_url(1))).to have_been_made.once
      end

      it "fetches the manifest and the shard again after 24 hours" do
        now = Time.now
        allow(Time).to receive(:now).and_return(now)
        source.rows(id1)
        allow(Time).to receive(:now).and_return(now + 86_401)
        source.rows(id1)
        expect(a_request(:get, manifest_url)).to have_been_made.twice
        expect(a_request(:get, shard_url(1))).to have_been_made.twice
      end
    end

    context "when the shard is absent (404)" do
      before { stub_request(:get, shard_url(1)).to_return(status: 404) }

      it "returns no rows: not found is an answer" do
        expect(source.rows(id1)).to eq []
      end

      it "does not fall back to the whole index" do
        source.rows(id1)
        expect(a_request(:get, /\.zip\z/)).not_to have_been_made
      end

      it "keeps the miss in memory" do
        2.times { source.rows(id1) }
        expect(a_request(:get, shard_url(1))).to have_been_made.once
      end
    end

    context "when the manifest has no shards" do
      let(:shards) { 0 }

      before do
        stub_request(:get, "#{pages}index-v2.zip").to_return(
          status: 200, body: zipped([{ id: id2, file: "f2" }, { id: id1, file: "f1" }]),
        )
      end

      it "returns the whole index named by the manifest, sorted" do
        expect(source.rows(id1)).to eq [{ id: id1, file: "f1" }, { id: id2, file: "f2" }]
      end
    end

    context "when the id has no root number" do
      let(:bare) { TestIdentifier.create(publisher: "ISO") }

      before do
        stub_request(:get, "#{pages}index-v2.zip")
          .to_return(status: 200, body: zipped([{ id: id1, file: "f1" }]))
      end

      it "returns the whole index" do
        expect(source.rows(bare)).to eq [{ id: id1, file: "f1" }]
        expect(a_request(:get, /shard-/)).not_to have_been_made
      end
    end

    context "when a transport error occurs" do
      it "raises Relaton::RequestError on a 5xx manifest" do
        stub_request(:get, manifest_url).to_return(status: 503)
        expect { source.rows(id1) }.to raise_error Relaton::RequestError, /503/
      end

      it "raises Relaton::RequestError on a 5xx shard" do
        stub_request(:get, shard_url(1)).to_return(status: 500)
        expect { source.rows(id1) }.to raise_error Relaton::RequestError, /500/
      end

      it "raises Relaton::RequestError on a truncated gzip body" do
        stub_request(:get, shard_url(1)).to_raise Zlib::BufError
        expect { source.rows(id1) }.to raise_error Relaton::RequestError
      end

      it "raises Relaton::RequestError on a network error" do
        stub_request(:get, shard_url(1)).to_timeout
        expect { source.rows(id1) }.to raise_error Relaton::RequestError
      end

      it "does not keep a failure in memory" do
        stub_request(:get, shard_url(1)).to_return({ status: 500 },
          { status: 200, body: [row(id1, "f1")].to_json })
        expect { source.rows(id1) }.to raise_error Relaton::RequestError
        expect(source.rows(id1)).to eq [{ id: id1, file: "f1" }]
      end
    end

    context "when the machine index is unusable" do
      it "raises Relaton::Index::Error when no manifest is published" do
        stub_request(:get, manifest_url).to_return(status: 404)
        expect { source.rows(id1) }.to raise_error Relaton::Index::Error, /manifest/
      end

      it "raises Relaton::Index::Error on a malformed manifest" do
        stub_request(:get, manifest_url).to_return(status: 200, body: "{")
        expect { source.rows(id1) }.to raise_error Relaton::Index::Error
      end

      it "raises Relaton::Index::Error on a lookup rule it does not know" do
        manifest["key"] = "rendered"
        stub_request(:get, manifest_url).to_return(status: 200, body: manifest.to_json)
        expect { source.rows(id1) }.to raise_error Relaton::Index::Error, /rendered/
      end

      it "raises Relaton::Index::Error on a row pubid cannot read" do
        stub_request(:get, shard_url(1)).to_return(
          status: 200, body: [{ "file" => "f", "id" => { "junk" => 1 } }].to_json,
        )
        expect { source.rows(id1) }.to raise_error Relaton::Index::Error
      end
    end
  end

  describe "#whole_index" do
    before do
      stub_request(:get, "#{pages}index-v2.zip")
        .to_return(status: 200, body: zipped([{ id: id1, file: "f1" }]))
    end

    it "fetches the monolith named by the manifest from the Pages site" do
      expect(source.whole_index).to eq [{ id: id1, file: "f1" }]
    end

    it "keeps it in memory" do
      2.times { source.whole_index }
      expect(a_request(:get, "#{pages}index-v2.zip")).to have_been_made.once
    end

    it "raises Relaton::Index::Error when the body is not a zip" do
      stub_request(:get, "#{pages}index-v2.zip").to_return(status: 200, body: "junk")
      expect { source.whole_index }.to raise_error Relaton::Index::Error
    end

    it "fetches each shard once when threads ask at the same time" do
      stub_request(:get, shard_url(1)).to_return(status: 200, body: [row(id1, "f1")].to_json)
      Array.new(8) { Thread.new { source.rows(id1) } }.each(&:join)
      expect(a_request(:get, manifest_url)).to have_been_made.once
      expect(a_request(:get, shard_url(1))).to have_been_made.once
    end

    it "does not write to the storage" do
      expect(Relaton::Index.config.storage).not_to receive(:write)
      source.whole_index
    end
  end
end
