require "webmock/rspec"
require "tmpdir"
require "zip"
require "yaml"

# The offline index the whole suite searches against: the published index,
# seeded straight into the Relaton::Index pool so no example downloads it.
#
# Built with `pubid_class:` — without it the rows stay raw hashes,
# `FileIO#sorted` stays false, and `Type#search` silently stops narrowing, so
# the suite would pass while testing something the runtime never does.
#
# Re-seeded in `before(:each)`, not only `before(:suite)`: `Index::Pool#type`
# replaces the pooled entry whenever `actual?` says no, and `DataFetcher#index`
# asks for the same type with `file:` but no `url:`. With `before(:suite)`
# alone, every example after the first data_fetcher one searched a producer
# index instead — and, because that one carries no url either, the consumer
# then built a THIRD type and went to the network for real. The pool key is
# `type.upcase.to_sym`, so the fetcher's `:ecma` and the consumer's `:ECMA`
# share one slot. (The OGC pattern.)
module EcmaIndexFixture
  def self.index_type
    @index_type ||= build
  end

  def self.build
    zip_path = File.join(__dir__, "..", "fixtures",
                         "#{Relaton::Ecma::INDEXFILE}.zip")
    yaml = Zip::File.open(zip_path) { |zip| zip.first.get_input_stream.read }
    file = File.join(Dir.mktmpdir("relaton-ecma-spec"),
                     "#{Relaton::Ecma::INDEXFILE}.yaml")
    File.write file, yaml, encoding: "UTF-8"

    type = Relaton::Index::Type.new(:ECMA, nil, file, nil,
                                    ::Pubid::Ecma::Identifier)
    type.index # force the deserialize + sort once, offline
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
