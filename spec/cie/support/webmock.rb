require "webmock/rspec"
require "zip"
require "yaml"
require "tmpdir"

INDEX_ZIP_PATH = File.join(__dir__, "..", "fixtures", "index-v2.zip")

# The offline pubid-keyed index-v2 fixture, built once per process and
# memoized (RSpec builds a fresh example-group instance per example, so
# re-reading and re-deserializing every row per example would be slow).
module CieIndexFixture
  def self.type
    @type ||= build
  end

  def self.build
    # Parse the pubid-backed index-v2 YAML from the fixture zip and deserialize
    # it via pubid_class (rows are `_type: pubid:cie:*` hashes). Written to a
    # temp file so Relaton::Index::Type reads it offline through FileIO.
    yaml = Zip::File.open(INDEX_ZIP_PATH) do |zip|
      zip.first.get_input_stream.read
    end
    index_file = File.join(Dir.mktmpdir("relaton-cie-spec"), "index-v2.yaml")
    File.write(index_file, yaml)

    type = Relaton::Index::Type.new(:cie, file: index_file, pubid_class: ::Pubid::Cie::Identifier)
    type.index # force the offline read + deserialize now, before net is blocked
    # actual? matches the remote lookups (url:, pages_url:) so the
    # producer-side find_or_create(:cie, file:, pubid_class:) still gets a
    # fresh instance.
    type.define_singleton_method(:actual?) do |**args|
      args.key?(:url) || args.key?(:pages_url)
    end
    type
  end

  # A producer-side `find_or_create(:cie, file: ...)` (actual? false for
  # `file:` args) replaces the pool entry with a fresh empty Type, so a
  # consumer example running after it would see an empty index — the
  # order-dependent "get CIE standard" failure. Re-seed before each example.
  def self.seed!
    Relaton::Index.pool.instance_variable_get(:@pool)[:CIE] = type
  end
end

RSpec.configure do |config|
  config.before(:suite) { CieIndexFixture.seed! }

  config.before(:each) { CieIndexFixture.seed! }

  config.before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
