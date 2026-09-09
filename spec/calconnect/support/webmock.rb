require "webmock/rspec"
require "tmpdir"
require "zip"
require "yaml"

# The offline index the suite searches against: the whole published
# `index-v2`, seeded straight into the Relaton::Index pool so no example
# downloads it.
#
# Built **with `pubid_class:`** — without it the rows stay raw hashes,
# `FileIO#sorted` stays false, and `Type#search` silently stops narrowing, so
# the suite would pass while exercising something the runtime never does.
#
# It is written to a temp file and read through `FileIO` rather than having
# `@index` stuffed in directly (which is what the v1 fixture used to do),
# because deserializing to pubid objects and setting `sorted` both happen on
# that read path. Stuffing raw rows in would skip both.
#
# Re-seeded in `before(:each)`, not only `before(:suite)`: `Index::Pool#type`
# replaces the pooled entry whenever `actual?` says no, and `DataFetcher#index`
# asks for the same `:CC` slot with `file:` but no `url:`. With a
# `before(:suite)` seed alone the fetcher evicts the fixture, and every later
# example goes to the network for real — which is how six examples used to die
# with `Errno::EPERM` on `~/.relaton`. The pool key is `type.upcase.to_sym`, so
# the fetcher's `:CC` and the consumer's `:CC` share one slot. (The ECMA/OGC
# pattern.)
module CalconnectIndexFixture
  def self.index_type
    @index_type ||= build
  end

  def self.build
    zip_path = File.join(__dir__, "..", "fixtures",
                         "#{Relaton::Calconnect::INDEXFILE}.zip")
    yaml = Zip::File.open(zip_path) { |zip| zip.first.get_input_stream.read }
    file = File.join(Dir.mktmpdir("relaton-calconnect-spec"),
                     "#{Relaton::Calconnect::INDEXFILE}.yaml")
    File.write file, yaml, encoding: "UTF-8"

    type = Relaton::Index::Type.new(:CC, nil, file, nil,
                                    ::Pubid::Calconnect::Identifier)
    type.index # force the deserialize + sort once, offline
    # Answers "actual" to the CONSUMER call, which passes `url:`, so a lookup
    # gets these rows instead of downloading. It answers false to the producer's
    # call, which passes no `url:` — and `Pool#type` REPLACES the pooled entry
    # whenever `actual?` says no, so `DataFetcher#index` really does evict this
    # fixture for the rest of that example. That is what the `before(:each)`
    # below repairs, and why `before(:suite)` alone is not enough.
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
