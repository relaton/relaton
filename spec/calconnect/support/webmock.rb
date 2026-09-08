require "webmock/rspec"
require "zip"
require "yaml"

# The offline index the suite searches against, seeded straight into the
# Relaton::Index pool so no example downloads it.
#
# Still the legacy v1: relaton-data-calconnect publishes no index-v2.zip yet, so
# the runtime reads INDEXFILE_V1. The consumer commit swaps the fixture for a
# verbatim cut of the published index-v2 and builds the Type with
# `pubid_class: ::Pubid::Calconnect::Identifier` — without which the rows stay
# raw hashes, `FileIO#sorted` stays false, and `Type#search` silently stops
# narrowing, so the suite would pass while exercising something the runtime
# never does.
#
# Re-seeded in `before(:each)`, not only `before(:suite)`: `Index::Pool#type`
# replaces the pooled entry whenever `actual?` says no, and `DataFetcher#index`
# now asks for the same `:CC` slot with a DIFFERENT file (index-v2.yaml). With a
# `before(:suite)` seed alone the fetcher evicts the fixture, and every later
# example goes to the network for real. The pool key is `type.upcase.to_sym`, so
# the producer and the consumer share one slot. (The ECMA/OGC pattern.)
module CalconnectIndexFixture
  def self.index_type
    @index_type ||= build
  end

  def self.build
    zip_path = File.join(__dir__, "..", "fixtures",
                         "#{Relaton::Calconnect::INDEXFILE_V1}.zip")
    yaml = Zip::File.open(zip_path) { |zip| zip.first.get_input_stream.read }

    type = Relaton::Index::Type.new(:CC, nil, "#{Relaton::Calconnect::INDEXFILE_V1}.yaml")
    type.instance_variable_set(:@index, YAML.safe_load(yaml, permitted_classes: [Symbol]))
    # Answers "actual" to the CONSUMER call, which passes `url:`, so a lookup
    # gets these rows instead of downloading. It answers false to the producer's
    # call, which passes no `url:` — and `Pool#type` REPLACES the pooled entry
    # whenever `actual?` says no, so `DataFetcher#index` really does evict this
    # fixture for the rest of that example. That is what the `before(:each)`
    # below repairs, and why `before(:suite)` alone is not enough. Do not read
    # this override as "the producer leaves the fixture alone" — it does not.
    type.define_singleton_method(:actual?) { |**args| args.key?(:url) }
    type
  end
end

RSpec.configure do |config|
  config.before(:suite) { CalconnectIndexFixture.index_type }

  config.before(:each) do
    Relaton::Index.pool.instance_variable_get(:@pool)[:CC] =
      CalconnectIndexFixture.index_type
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
