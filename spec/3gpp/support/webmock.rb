require "webmock/rspec"
require "tmpdir"
require "zip"

# The offline index the whole suite searches against: a curated subset of the
# published index, seeded straight into the Relaton::Index pool so no example
# downloads it. `rake spec:update_index_3gpp` regenerates it; see
# tasks/index_fixture_3gpp.rb for what each document group is for.
#
# Built with `pubid_class:` — without it the rows stay raw hashes,
# `FileIO#sorted` stays false, and `Type#search` silently stops narrowing, so
# the suite would pass while testing something the runtime never does.
#
# Re-seeded in `before(:each)`, not only `before(:suite)`: `Index::Pool#type`
# replaces the pooled entry whenever `actual?` says no, and `DataFetcher#index`
# asks for the same type with `file:` but no `url:`. `before(:suite)` alone
# would leave a later example searching a producer index. `Pool#type` upcases
# its key, so `Bibliography`'s "3GPP" and `DataFetcher`'s "3gpp" are the SAME
# pooled entry, `:"3GPP"`. (The W3C/IALA precedent.)
module ThreeGppIndexFixture
  def self.index_type
    @index_type ||= build
  end

  # `Relaton::ThreeGpp` is not loaded yet when this file is required
  # (spec_helper loads support/ before the flavor), so the constant is read
  # lazily here.
  def self.build
    zip_path = File.join(__dir__, "..", "fixtures",
                         "#{Relaton::ThreeGpp::INDEXFILE}.zip")
    yaml = Zip::File.open(zip_path) { |zip| zip.first.get_input_stream.read }
    file = File.join(Dir.mktmpdir("relaton-3gpp-spec"),
                     "#{Relaton::ThreeGpp::INDEXFILE}.yaml")
    File.write file, yaml, encoding: "UTF-8"

    type = Relaton::Index::Type.new("3GPP", nil, file, nil,
                                    ::Pubid::Tgpp::Identifier)
    type.index # force the deserialize + sort once, offline
    type.define_singleton_method(:actual?) { |**args| args.key?(:url) }
    type
  end
end

RSpec.configure do |config|
  config.before(:suite) { ThreeGppIndexFixture.index_type }

  config.before(:each) do
    Relaton::Index.pool.instance_variable_get(:@pool)[:"3GPP"] =
      ThreeGppIndexFixture.index_type
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
