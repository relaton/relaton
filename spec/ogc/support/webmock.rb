require "webmock/rspec"
require "tmpdir"
require "zip"
require "yaml"
require "relaton/ogc"

# The offline index the whole suite searches against: the published index,
# seeded straight into the Relaton::Index pool so no example downloads it.
#
# Built with `pubid_class:` — without it the rows stay raw hashes,
# `FileIO#sorted` stays false, and `Type#search` silently stops narrowing, so
# the suite would pass while testing something the runtime never does.
#
# Re-seeded in `before(:each)`, not only `before(:suite)`: `Index::Pool#type`
# replaces the pooled entry whenever `actual?` says no, and `DataFetcher#index`
# asks for the same type with `file:` but no `url:`. `before(:suite)` alone
# would leave a later example searching a producer index. The pool key is
# `type.upcase.to_sym`, so the flavor's `:ogc` is pooled as `:OGC`.
module OgcIndexFixture
  def self.index_type
    @index_type ||= build
  end

  def self.build
    zip_path = File.join(__dir__, "..", "fixtures",
                         "#{Relaton::Ogc::INDEXFILE}.zip")
    yaml = Zip::File.open(zip_path) { |zip| zip.first.get_input_stream.read }
    file = File.join(Dir.mktmpdir("relaton-ogc-spec"),
                     "#{Relaton::Ogc::INDEXFILE}.yaml")
    File.write file, yaml, encoding: "UTF-8"

    type = Relaton::Index::Type.new(:ogc, nil, file, nil,
                                    ::Pubid::Ogc::Identifier)
    type.index # force the deserialize + sort once, offline
    type.define_singleton_method(:actual?) { |**args| args.key?(:url) }
    type
  end
end

RSpec.configure do |config|
  config.before(:suite) { OgcIndexFixture.index_type }

  config.before(:each) do
    Relaton::Index.pool.instance_variable_get(:@pool)[:OGC] =
      OgcIndexFixture.index_type
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
