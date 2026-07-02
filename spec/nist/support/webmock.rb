require "webmock/rspec"
require "zip"
require "yaml"
require "json"
require "tmpdir"

INDEX_ZIP_PATH = File.join(__dir__, "..", "fixtures", "index-v2.zip")
PUBS_EXPORT_ZIP_PATH = File.join(__dir__, "..", "fixtures", "pubs-export.zip")

RSpec.configure do |config|
  config.before(:suite) do
    # Parse index-v2 YAML from fixture zip once and deserialize via pubid_class
    yaml = Zip::File.open(INDEX_ZIP_PATH) do |zip|
      zip.first.get_input_stream.read
    end
    index_file = File.join(Dir.mktmpdir("relaton-nist-spec"), "index-v2.yaml")
    File.write(index_file, yaml)

    type = Relaton::Index::Type.new(:nist, nil, index_file, nil, ::Pubid::Nist::Identifier)
    type.index # force the offline read + deserialize now, before net is blocked
    # actual? only matches the remote (url:) lookup so the producer-side
    # find_or_create(:nist, file:, pubid_class:) still gets a fresh instance.
    type.define_singleton_method(:actual?) { |**args| args.key?(:url) }

    # Inject into pool so find_or_create(:nist, url: ...) returns this instance
    Relaton::Index.pool.instance_variable_get(:@pool)[:NIST] = type

    # Pre-load PubsExport data from fixture zip
    pubs_data = Zip::File.open(PUBS_EXPORT_ZIP_PATH) do |zf|
      JSON.parse(zf.first.get_input_stream.read)
    end
    Relaton::Nist::PubsExport.instance.instance_variable_set(:@data, pubs_data)
  end

  config.before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
