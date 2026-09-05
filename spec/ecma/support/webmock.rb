require "webmock/rspec"
require "zip"
require "yaml"

# The offline index the whole suite searches against, seeded straight into the
# Relaton::Index pool so no example downloads it.
#
# Still `INDEXFILE_V1`: the gem PRODUCES the pubid `index-v2` now, but
# Bibliography still reads the bespoke v1 index until relaton-data-ecma
# republishes. This fixture moves with the consumer migration.
#
# Re-seeded in `before(:each)`, not only `before(:suite)`: `Index::Pool#type`
# replaces the pooled entry whenever `actual?` says no, and `DataFetcher#index`
# asks for the same type with `file:` but no `url:`. With `before(:suite)`
# alone, every example after the first data_fetcher one searched a producer
# index instead — and, because that one carries no url either, the consumer
# then built a THIRD type and went to the network for real. (The OGC pattern.)
module EcmaIndexFixture
  def self.index_type
    @index_type ||= build
  end

  def self.build
    zip_path = File.join(__dir__, "..", "fixtures",
                         "#{Relaton::Ecma::INDEXFILE_V1}.zip")
    yaml = Zip::File.open(zip_path) { |zip| zip.first.get_input_stream.read }
    index_data = YAML.safe_load(yaml, permitted_classes: [Symbol])

    type = Relaton::Index::Type.new(:ECMA, nil, "#{Relaton::Ecma::INDEXFILE_V1}.yaml")
    type.instance_variable_set(:@index, index_data)
    type.define_singleton_method(:actual?) { |**args| args.key?(:url) }
    type
  end
end

RSpec.configure do |config|
  config.before(:suite) { EcmaIndexFixture.index_type }

  config.before(:each) do
    Relaton::Index.pool.instance_variable_get(:@pool)[:ECMA] =
      EcmaIndexFixture.index_type
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
