require "canon"
require "webmock/rspec"
require "tmpdir"
require "zip"
require "relaton/iala"

# The offline index the whole suite searches against: a curated subset of the
# published `index-v2`, seeded straight into the Relaton::Index pool so no
# example downloads it.
#
# Built with `pubid_class:` — without it the rows stay raw hashes,
# `FileIO#sorted` stays false, and `Type#search` silently stops narrowing, so
# the suite would pass while testing something the runtime never does.
#
# Re-seeded in `before(:each)` because `Index::Pool#type` replaces the pooled
# entry whenever `actual?` says no; the stubbed `actual?` keeps the fixture in
# place for the `url:`-less lookups too. `Pool#type` upcases its key, so
# the pooled entry is `:IALA` even though the flavor asks for `:iala`.
# (The W3C precedent; see
# spec/w3c/support/webmock.rb.)
module IalaIndexFixture
  def self.index_type
    @index_type ||= build
  end

  # `Relaton::Iala` is loaded above, but read the constant here anyway so the
  # fixture name always follows INDEXFILE.
  def self.build
    zip_path = File.join(__dir__, "..", "fixtures",
                         "#{Relaton::Iala::INDEXFILE}.zip")
    yaml = Zip::File.open(zip_path) { |zip| zip.first.get_input_stream.read }
    file = File.join(Dir.mktmpdir("relaton-iala-spec"),
                     "#{Relaton::Iala::INDEXFILE}.yaml")
    File.write file, yaml, encoding: "UTF-8"

    type = Relaton::Index::Type.new(:iala, nil, file, nil,
                                    ::Pubid::Iala::Identifier)
    type.index # force the deserialize + sort once, offline
    type.define_singleton_method(:actual?) { |**args| args.key?(:url) }
    type
  end
end

RSpec.configure do |config|
  config.before(:suite) { IalaIndexFixture.index_type }

  config.before(:each) do
    Relaton::Index.pool.instance_variable_get(:@pool)[:IALA] =
      IalaIndexFixture.index_type
    WebMock.reset!
    WebMock.disable_net_connect!(allow_localhost: true)
  end
end
