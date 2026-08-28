require "webmock/rspec"
require "tmpdir"
require "zip"

# The offline index the whole suite searches against: the published
# `index-v2`, seeded straight into the Relaton::Index pool so no example
# downloads it.
#
# Built with `pubid_class:` — without it the rows stay raw hashes,
# `FileIO#sorted` stays false, and `Type#search` silently stops narrowing, so
# the suite would pass while testing something the runtime never does.
#
# Re-seeded in `before(:each)`, not only `before(:suite)`: `Index::Pool#type`
# replaces the pooled entry whenever `actual?` says no, and `DataFetcher#index`
# asks for the same `:W3C` type with `file:` but no `url:`. `before(:suite)`
# alone would leave a later example searching a producer index. (IANA hit this
# first; see spec/iana/support/webmock.rb.)
module W3cIndexFixture
  def self.index_type
    @index_type ||= build
  end

  # `Relaton::W3c` is not loaded yet when this file is required (spec_helper
  # loads support/ before the flavor), so the constant is read lazily here.
  def self.build
    zip_path = File.join(__dir__, "..", "fixtures",
                         "#{Relaton::W3c::INDEXFILE}.zip")
    yaml = Zip::File.open(zip_path) { |zip| zip.first.get_input_stream.read }
    file = File.join(Dir.mktmpdir("relaton-w3c-spec"),
                     "#{Relaton::W3c::INDEXFILE}.yaml")
    File.write file, yaml, encoding: "UTF-8"

    type = Relaton::Index::Type.new(:W3C, nil, file, nil,
                                    ::Pubid::W3c::Identifier)
    type.index # force the deserialize + sort once, offline
    type.define_singleton_method(:actual?) { |**args| args.key?(:url) }
    type
  end
end

RSpec.configure do |config|
  config.before(:suite) { W3cIndexFixture.index_type }

  config.before(:each) do
    Relaton::Index.pool.instance_variable_get(:@pool)[:W3C] =
      W3cIndexFixture.index_type
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
