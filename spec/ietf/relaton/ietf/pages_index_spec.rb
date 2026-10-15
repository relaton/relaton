# frozen_string_literal: true

require "zlib"

# The Pages machine index (relaton#206, the W3C pilot's contract): the
# manifest + one shard per query, no data-repo zip in the path.
RSpec.describe Relaton::Ietf::Scraper, "-- the Pages machine index (relaton#206, the W3C pilot's contract): the manifest + one shard per query, no data-repo zip in the path" do
  let(:pages) { Relaton::Ietf::PAGES_URL }
  let(:shards) { 2048 }
  let(:fixture_rows) { @rows }

  def shard_of(number)
    format("%<pages>sindex/shard-%<n>05d.json", pages: pages, n: Zlib.crc32(number) % shards)
  end

  before do
    # The suite preload makes every Type stale; the pool must keep the
    # Pages type here, as it does at runtime. The preloaded type is
    # saved and restored around each example: the whole suite shares it
    # (the shard client holds no disk cache), so closing :IETF here must
    # not leak into the other examples.
    allow_any_instance_of(Relaton::Index::Type).to receive(:actual?).and_call_original
    pool = Relaton::Index.pool.instance_variable_get(:@pool)
    @saved_type = pool[:IETF]
    @rows = @saved_type.index
    stub_request(:get, "#{pages}index/manifest.json").to_return(
      status: 200,
      body: { version: 2, index: "index-v2", count: @rows.size,
              shards: shards, key: "root-number", algorithm: "crc32" }.to_json,
    )
    Relaton::Index.close(:IETF)
  end

  after do
    pool = Relaton::Index.pool.instance_variable_get(:@pool)
    pool[:IETF] = @saved_type
  end

  it "opens the machine index on the Pages site" do
    expect(Relaton::Index).to receive(:find_or_create).with(
      :IETF, pages_url: pages, pubid_class: ::Pubid::Ietf::Identifier
    ).and_call_original
    described_class.send(:index)
  end

  it "fetches the document through its shard, without the whole index" do
    row = fixture_rows.find { |r| r[:file]&.end_with?(".yaml") }
    number = row[:id].root.number.to_s
    body = [{ r: row[:id].to_s, file: row[:file], id: row[:id].to_hash }].to_json
    stub_request(:get, shard_of(number)).to_return(status: 200, body: body)
    stub_request(:get, "#{described_class::IETF}#{row[:file]}")
      .to_return(status: 200, body: <<~YAML)
        ---
        docidentifier:
        - type: IETF
          content: #{row[:id].to_s}
      YAML

    doc = described_class.send(:fetch_doc, row[:id])

    expect(doc).to be_a Relaton::Ietf::ItemData
    expect(doc.docidentifier.first.content).to eq row[:id].to_s
    expect(a_request(:get, /index-v2\.zip\z/)).not_to have_been_made
  end

  it "raises Relaton::RequestError when the Pages site fails" do
    row = fixture_rows.first
    stub_request(:get, shard_of(row[:id].root.number.to_s)).to_return(status: 503)
    expect { described_class.send(:fetch_doc, row[:id]) }
      .to raise_error Relaton::RequestError
  end
end
