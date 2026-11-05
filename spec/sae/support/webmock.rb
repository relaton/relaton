require "webmock/rspec"
require "tmpdir"
require "relaton/sae"

# The offline index the consumer specs search: `fixtures/index-v2.yaml`, the
# index that `Relaton::Sae::DataFetcher` writes from the Crossref page fixtures
# (`fixtures/crossref/`), seeded straight into the Relaton::Index pool so no
# example reads the Pages site.
#
# Built with `pubid_class:`, as the runtime builds it: without it the rows stay
# raw hashes and `Type#search` stops narrowing, so the suite would pass while
# testing something the runtime never does. Re-seeded in `before(:each)`,
# because `Index::Pool#type` replaces the pooled entry when `actual?` says no,
# and the data-fetcher examples ask for the same pool slot with `file:` only.
# (The IALA/ECMA pattern.)
module SaeIndexFixture
  def self.index_type
    @index_type ||= build
  end

  def self.build
    src = File.join(__dir__, "..", "fixtures", "#{Relaton::Sae::INDEXFILE}.yaml")
    file = File.join(Dir.mktmpdir("relaton-sae-spec"), "#{Relaton::Sae::INDEXFILE}.yaml")
    File.write file, File.read(src, encoding: "UTF-8"), encoding: "UTF-8"
    type = Relaton::Index::Type.new(:sae, file: file, pubid_class: ::Pubid::Sae::Identifier)
    type.index # deserialize and sort once, offline
    type.define_singleton_method(:actual?) do |**args|
      args.key?(:pages_url) || args.key?(:url)
    end
    type
  end
end

RSpec.configure do |config|
  config.before(:each) do |example|
    unless example.metadata[:no_index_fixture]
      Relaton::Index.pool.instance_variable_get(:@pool)[:SAE] =
        SaeIndexFixture.index_type
    end
    WebMock.reset!
    WebMock.disable_net_connect!
  end

  config.after(:each, :no_index_fixture) do
    Relaton::Index.pool.instance_variable_get(:@pool).delete(:SAE)
  end
end
