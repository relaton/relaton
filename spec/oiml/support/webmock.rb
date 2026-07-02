require "webmock/rspec"
require "zip"
require "tmpdir"
require "relaton/oiml"

# Data files (data/*.yaml) are served from fixtures/; the index is
# pre-loaded from the committed zip fixture (below), so no HTTP request for it
# is ever made.
FIXTURES_DIR = File.expand_path("../fixtures", __dir__)
ENDPOINT_PATH = URI(Relaton::Oiml::Bibliography::ENDPOINT).path
INDEX_ZIP_PATH = File.join(FIXTURES_DIR, "#{Relaton::Oiml::INDEXFILE}.zip")

RSpec.configure do |config|
  config.before(:suite) do
    # Load the offline index fixture into the Relaton::Index pool so lookups
    # resolve without fetching the remote zip. Pass pubid_class so each row's
    # :id is rebuilt into a Pubid::Oiml::Identifier via from_hash.
    yaml = Zip::File.open(INDEX_ZIP_PATH) { |zip| zip.first.get_input_stream.read }
    index_file = File.join(Dir.mktmpdir("relaton-oiml-spec"), "#{Relaton::Oiml::INDEXFILE}.yaml")
    File.write(index_file, yaml)

    type = Relaton::Index::Type.new(:oiml, nil, index_file, nil, ::Pubid::Oiml::Identifier)
    type.index
    type.define_singleton_method(:actual?) { |**args| args.key?(:url) }

    Relaton::Index.pool.instance_variable_get(:@pool)[:OIML] = type
  end

  config.before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!

    WebMock.stub_request(:get, /#{Regexp.escape Relaton::Oiml::Bibliography::ENDPOINT}/)
      .to_return do |request|
        rel = request.uri.path.sub(ENDPOINT_PATH, "")
        file = File.join(FIXTURES_DIR, rel)
        if File.file?(file)
          { status: 200, body: File.read(file, encoding: "UTF-8") }
        else
          { status: 404, body: "Not Found" }
        end
      end
  end
end
