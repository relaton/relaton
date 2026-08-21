require "webmock/rspec"
require "zip"
require "tmpdir"
require "relaton/iana"

INDEX_ZIP_PATH = File.join(__dir__, "..", "fixtures", "#{Relaton::Iana::INDEXFILE}.zip")

# The offline pubid-keyed index-v2 fixture, built once per process.
#
# Memoized here rather than in an @ivar: RSpec builds a fresh example-group
# instance per example, so an @ivar would re-read and re-deserialize all 3405
# rows for every example (17s vs 0.8s for the suite).
module IanaIndexFixture
  def self.index_type
    @index_type ||= build
  end

  def self.build
    yaml = Zip::File.open(INDEX_ZIP_PATH) do |zip|
      zip.first.get_input_stream.read
    end
    # Type loads from a file path, so extract the fixture zip to an ephemeral
    # temp file; only the zip is committed.
    index_file = File.join(Dir.mktmpdir("relaton-iana-spec"), "#{Relaton::Iana::INDEXFILE}.yaml")
    File.write(index_file, yaml)

    # pubid_class rebuilds each row's :id into a
    # Pubid::Iana::Identifiers::Registry via from_hash; `#index` forces the
    # offline read + deserialize + sort now, before the net is blocked.
    type = Relaton::Index::Type.new(:iana, nil, index_file, nil, ::Pubid::Iana::Identifier)
    type.index
    # Claim only the consumer (`url:`) lookup, so DataFetcher's producer-side
    # `find_or_create(file:, pubid_class:)` still gets a fresh, empty Type.
    type.define_singleton_method(:actual?) { |**args| args.key?(:url) }
    type
  end
end

def iana_index_fixture
  IanaIndexFixture.index_type
end

RSpec.configure do |config|
  config.before(:suite) { iana_index_fixture }

  config.before(:each) do
    # Re-seeding every example is not belt-and-braces: `Pool#type` replaces the
    # pooled entry whenever `actual?` says no, and `DataFetcher#index` asks for
    # the SAME :iana type with `file:` but no `url:` — so any example that
    # touches the producer evicts the fixture and leaves later consumer lookups
    # trying to download the real zip. This makes the suite order-independent.
    Relaton::Index.pool.instance_variable_get(:@pool)[:IANA] = iana_index_fixture
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
