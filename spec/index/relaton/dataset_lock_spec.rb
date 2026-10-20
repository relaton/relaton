# frozen_string_literal: true

require "digest"

describe Relaton::Index::DatasetLock do
  let(:pages_url) { "https://relaton.github.io/relaton-data-iso/" }
  let(:data) { "the published index bytes" }
  let(:manifest) do
    { "version" => 2, "index" => "index-v2", "count" => 3, "shards" => 0,
      "key" => "root-number", "algorithm" => "crc32",
      "generated" => "2026-10-20",
      "sha256" => Digest::SHA256.hexdigest(data),
      "bytes" => data.bytesize }
  end
  let(:lock) do
    described_class.from_manifest(pages_url, manifest,
                                  captured_at: "2026-10-20T00:00:00Z")
  end

  it "captures the manifest's content address" do
    expect(lock.sha256).to eq(Digest::SHA256.hexdigest(data))
    expect(lock.bytes).to eq(data.bytesize)
    expect(lock.index).to eq("index-v2")
    expect(lock.count).to eq(3)
    expect(lock.generated).to eq("2026-10-20")
    expect(lock.captured_at).to eq("2026-10-20T00:00:00Z")
  end

  it "builds the published zip URL from the site and index name" do
    expect(lock.zip_url).to eq("https://relaton.github.io/relaton-data-iso/index-v2.zip")
  end

  it "round-trips through YAML" do
    round = described_class.from_yaml(lock.to_yaml)

    expect(round.to_hash).to eq(lock.to_hash)
    expect(round.verify(data)).to be true
  end

  it "refuses a manifest with no content address" do
    manifest.delete("sha256")

    expect { described_class.from_manifest(pages_url, manifest) }
      .to raise_error(Relaton::Index::Error, /no sha256/)
  end

  it "refuses a malformed content address" do
    manifest["sha256"] = "not-a-hash"

    expect { described_class.from_manifest(pages_url, manifest) }
      .to raise_error(Relaton::Index::Error, /no sha256/)
  end

  it "verifies the pinned bytes" do
    expect(lock.verify(data)).to be true
  end

  it "rejects different bytes" do
    expect { lock.verify("tampered") }
      .to raise_error(Relaton::Index::Error, /hash mismatch/)
  end

  it "captures from a fetched manifest" do
    fetcher = ->(_url, **) { manifest }

    captured = described_class.capture(pages_url, fetcher: fetcher)

    expect(captured.sha256).to eq(manifest["sha256"])
    expect(captured.count).to eq(3)
  end
end
