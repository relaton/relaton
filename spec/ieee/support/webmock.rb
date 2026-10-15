require "webmock/rspec"
require "zip"
require "yaml"
require "tmpdir"

INDEX_ZIP_PATH = File.join(__dir__, "..", "fixtures", "index-v2.zip")

RSpec.configure do |config|
  config.before(:suite) do
    # Extract the index-v2 YAML from the fixture zip, then deserialize it through
    # the flavor's pubid_class so rows become Pubid::Ieee::Identifier objects
    # (index-v2 stores the structured `_type: pubid:ieee:*` form).
    yaml = Zip::File.open(INDEX_ZIP_PATH) do |zip|
      zip.first.get_input_stream.read
    end
    index_file = File.join(Dir.mktmpdir("relaton-ieee-spec"), "index-v2.yaml")
    File.write(index_file, yaml)

    type = Relaton::Index::Type.new(:ieee, file: index_file, pubid_class: ::Pubid::Ieee::Identifier)
    type.index # force the offline read + deserialize + sort now, before net is blocked
    # actual? matches the remote lookups (the legacy url: cache removal and
    # the pages_url: machine index, relaton#206) so the producer-side
    # find_or_create(:ieee, file:, pubid_class:) still gets a fresh instance.
    type.define_singleton_method(:actual?) do |**args|
      args.key?(:url) || args.key?(:pages_url)
    end

    # Inject into the pool so Bibliography.search's find_or_create(:ieee, url: ...)
    # returns this pre-loaded instance instead of downloading.
    Relaton::Index.pool.instance_variable_get(:@pool)[:IEEE] = type
  end

  config.before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
