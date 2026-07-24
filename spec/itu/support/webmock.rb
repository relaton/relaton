require "webmock/rspec"
require "zip"
require "yaml"
require "tmpdir"

INDEX_ZIP_PATH = File.join(__dir__, "..", "fixtures", "index-v2.zip")

RSpec.configure do |config|
  itu_index_type = nil

  config.before(:suite) do
    # Parse the pubid-backed index-v2 YAML from the fixture zip and deserialize
    # it via pubid_class (rows are `_type: pubid:itu:*` hashes). Written to a
    # temp file so Relaton::Index::Type reads it offline through FileIO.
    yaml = Zip::File.open(INDEX_ZIP_PATH) do |zip|
      zip.first.get_input_stream.read
    end
    index_file = File.join(Dir.mktmpdir("relaton-itu-spec"), "index-v2.yaml")
    File.write(index_file, yaml)

    itu_index_type = Relaton::Index::Type.new(:itu, nil, index_file, nil, ::Pubid::Itu::Identifier)
    itu_index_type.index # force the offline read + deserialize now, before net is blocked
    # actual? only matches the remote (url:) lookup so the producer-side
    # find_or_create(:itu, file:, pubid_class:) still gets a fresh instance.
    itu_index_type.define_singleton_method(:actual?) { |**args| args.key?(:url) }
  end

  config.before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!
    # Re-seat the offline fixture before every example. A producer-side
    # find_or_create(:itu, file:) in another example evicts the url-serving
    # fixture from the shared pool (Pool#type replaces a non-actual entry), so
    # restore it here — otherwise a later consumer lookup rebuilds a
    # network-backed Type and hits the blocked net. In production the producer
    # and consumer run in separate processes, so this eviction is a spec-only
    # artifact of sharing one Relaton::Index pool.
    Relaton::Index.pool.instance_variable_get(:@pool)[:ITU] = itu_index_type
  end
end
