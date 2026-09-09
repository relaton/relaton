require "webmock/rspec"
require "tmpdir"
require "zip"
require "yaml"
# spec_helper loads this support file BEFORE the flavor, and the fixture path
# is named from the flavor's own constant.
require "relaton/oasis"

# The offline index the whole suite searches against: the published index (605
# rows, verbatim), seeded straight into the Relaton::Index pool so no example
# downloads it. Refresh it with `rake spec:update_index_oasis`.
#
# Built with `pubid_class:` — without it the rows stay raw hashes,
# `FileIO#sorted` stays false, and `Type#search` silently stops narrowing, so
# the suite would pass while testing something the runtime never does.
#
# Re-seeded in `before(:each)`, not only `before(:suite)`: `Index::Pool#type`
# replaces the pooled entry whenever `actual?` says no, and `DataFetcher#index`
# asks for the same type with `file:` but no `url:`. `before(:suite)` alone
# would leave a later example searching a producer index. The pool key is
# `type.upcase.to_sym`, so the flavor's `:oasis` is pooled as `:OASIS`.
module OasisIndexFixture
  def self.index_type
    @index_type ||= build
  end

  def self.build
    zip_path = File.join(__dir__, "..", "fixtures",
                         "#{Relaton::Oasis::INDEXFILE}.zip")
    yaml = Zip::File.open(zip_path) { |zip| zip.first.get_input_stream.read }
    file = File.join(Dir.mktmpdir("relaton-oasis-spec"),
                     "#{Relaton::Oasis::INDEXFILE}.yaml")
    # `binwrite`, not `File.write(..., encoding: "UTF-8")`. The zip entry comes
    # back ASCII-8BIT, and the OASIS index carries non-ASCII bytes (`\xC2` — a
    # non-breaking space in one slug), which the transcode raises on. This is
    # the same invariant `Index::FileStorage#write` documents; a byte-verbatim
    # write round-trips, because `FileIO#read` decodes as UTF-8.
    File.binwrite file, yaml

    type = Relaton::Index::Type.new(:oasis, nil, file, nil,
                                    ::Pubid::Oasis::Identifier)
    type.index # force the deserialize + sort once, offline
    type.define_singleton_method(:actual?) { |**args| args.key?(:url) }
    type
  end
end

RSpec.configure do |config|
  config.before(:suite) { OasisIndexFixture.index_type }

  config.before(:each) do
    Relaton::Index.pool.instance_variable_get(:@pool)[:OASIS] =
      OasisIndexFixture.index_type
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
