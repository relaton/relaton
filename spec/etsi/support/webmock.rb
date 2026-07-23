require "webmock/rspec"
require "zip"
require "yaml"
require "tmpdir"

INDEX_ZIP_PATH = File.join(__dir__, "..", "fixtures", "index-v2.zip")

RSpec.configure do |config|
  config.before(:suite) do
    # Parse the pubid-backed index-v2 YAML from the fixture zip and deserialize
    # it via pubid_class (rows are `_type: pubid:etsi:*` hashes). Written to a
    # temp file so Relaton::Index::Type reads it offline through FileIO.
    yaml = Zip::File.open(INDEX_ZIP_PATH) do |zip|
      zip.first.get_input_stream.read
    end
    index_file = File.join(Dir.mktmpdir("relaton-etsi-spec"), "index-v2.yaml")
    File.write(index_file, yaml)

    type = Relaton::Index::Type.new(:etsi, nil, index_file, nil, ::Pubid::Etsi::Identifier)
    type.index # force the offline read + deserialize now, before net is blocked
    # actual? only matches the remote (url:) lookup so the producer-side
    # find_or_create(:etsi, file:, pubid_class:) still gets a fresh instance.
    type.define_singleton_method(:actual?) { |**args| args.key?(:url) }

    Relaton::Index.pool.instance_variable_get(:@pool)[:ETSI] = type
  end

  config.before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
