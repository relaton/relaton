require "canon"
require "webmock/rspec"
require "tmpdir"
require "relaton/easc"

# Offline retrieval fixtures. The EASC index is built in-memory from
# Pubid::Easc identifiers (so each row round-trips through
# `from_hash`/`to_hash` exactly like a published `relaton-data-easc`
# index-v2), pre-loaded into the Relaton::Index pool, and per-document
# YAML is served from spec/easc/fixtures/data/*.yaml by WebMock. No
# request ever hits the network.
FIXTURES_DIR = File.expand_path("../fixtures", __dir__)
ENDPOINT_PATH = URI(Relaton::Easc::Bibliography::ENDPOINT).path

# code -> data file, keyed on the canonical Cyrillic citation. The last row
# points at a data file that is intentionally absent from fixtures/ so a spec
# can exercise the "indexed but data missing" HTTP-404 path.
INDEX_ROWS = {
  "ПМГ 03-2025" => "data/pmg-03-2025.yaml",
  "РМГ 151-2025" => "data/rmg-151-2025.yaml",
  "ПМГ 99-2000" => "data/pmg-99-2000-missing.yaml",
}.freeze

RSpec.configure do |config|
  config.before(:suite) do
    # Serialize the pubid rows to a `_type:`-structured index-v2.yaml, then load
    # it back through a Relaton::Index::Type with the flavor pubid_class so each
    # row's :id is deserialized into a Pubid::Easc identifier — the same path a
    # downloaded index takes.
    index = INDEX_ROWS.map do |code, file|
      { id: ::Pubid::Easc.parse(code).to_hash, file: file }
    end
    index_file = File.join(Dir.mktmpdir("relaton-easc-spec"), "#{Relaton::Easc::INDEXFILE}.yaml")
    File.write(index_file, index.to_yaml)

    type = Relaton::Index::Type.new(:easc, nil, index_file, nil, ::Pubid::Easc::Identifier)
    type.index
    type.define_singleton_method(:actual?) { |**args| args.key?(:url) }

    Relaton::Index.pool.instance_variable_get(:@pool)[:EASC] = type
  end

  config.before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!(allow_localhost: true)

    WebMock.stub_request(:get, /#{Regexp.escape Relaton::Easc::Bibliography::ENDPOINT}/)
      .to_return do |request|
        rel = request.uri.path.sub(ENDPOINT_PATH, "")
        file = File.join(FIXTURES_DIR, rel)
        if File.file?(file)
          { status: 200, body: File.read(file, encoding: "UTF-8") }
        else
          { status: 404, body: "Not Found" }
        end
      end
  end
end
