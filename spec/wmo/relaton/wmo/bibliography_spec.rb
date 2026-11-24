# frozen_string_literal: true

require "zlib"
require "pubid"

RSpec.describe Relaton::Wmo::Bibliography do
  # The real Pages contract (Relaton::Index::ShardSource): manifest names
  # the shard count and key rule; a query reads only its own shard. One
  # shard keeps the arithmetic trivial for every row in the fixture.
  let(:pages) { Relaton::Wmo::PAGES_URL }
  let(:record_yaml) do
    {
      "id" => "rec",
      "type" => "standard",
      "docidentifier" => [{ "content" => "WMO-No. 8", "type" => "WMO", "primary" => true }],
      "title" => [{ "content" => "Guide to Instruments and Methods of Observation",
                    "language" => "eng", "type" => "main" }],
      "docnumber" => "8",
      "ext" => { "doctype" => { "content" => "technical-regulations" }, "flavor" => "wmo" },
    }.to_yaml
  end

  def row(id_string, file)
    { "id" => ::Pubid::Wmo.parse(id_string).to_hash.transform_keys(&:to_s),
      "file" => file }
  end

  before do
    manifest = { "version" => 2, "index" => "index-v2", "count" => 2,
                 "shards" => 1, "key" => "root-number",
                 "algorithm" => "crc32", "generated" => "2026-11-24" }
    shard = [row("WMO-No. 8", "data/wmo-no-8.yaml"),
             row("GAW Report No. 234", "data/gaw-report-no-234.yaml")]
    stub_request(:get, "#{pages}index/manifest.json")
      .to_return(status: 200, body: JSON.generate(manifest))
    stub_request(:get, "#{pages}index/shard-00000.json")
      .to_return(status: 200, body: JSON.generate(shard))
    stub_request(:get, "#{described_class::ENDPOINT}data/wmo-no-8.yaml")
      .to_return(status: 200, body: record_yaml)
  end

  it "resolves a canonical series-head reference and returns the record" do
    item = described_class.get("WMO-No. 8")
    expect(item).to be_a(Relaton::Wmo::ItemData)
    expect(item.docidentifier.first.content).to eq "WMO-No. 8"
    expect(item.title.first.content.to_s)
      .to eq "Guide to Instruments and Methods of Observation"
    expect(item.fetched).to eq Date.today.to_s
  end

  it "returns nil when the reference parses but no row matches" do
    expect(described_class.get("WMO/TD-No. 9999")).to be_nil
  end

  it "reads a reference pubid cannot parse as a miss, not an error" do
    expect(described_class.get("WMO Annual Report")).to be_nil
  end
end
