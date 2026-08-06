require "webmock/rspec"
require "zip"
require "yaml"
require "tmpdir"
require "relaton/bipm"

INDEX_ZIP_PATH = File.join(__dir__, "..", "fixtures", "index-v2.zip")

RSpec.configure do |config|
  config.before(:suite) do
    # Load the offline pubid-backed index-v2 fixture into the Relaton::Index
    # pool so lookups resolve without fetching the remote zip. Pass pubid_class
    # so each row's :id is rebuilt into a Pubid::Bipm::Identifier via from_hash.
    yaml = Zip::File.open(INDEX_ZIP_PATH) { |zip| zip.first.get_input_stream.read }
    index_file = File.join(Dir.mktmpdir("relaton-bipm-spec"), "index-v2.yaml")
    File.write(index_file, yaml)

    type = Relaton::Index::Type.new(:bipm, nil, index_file, nil, ::Pubid::Bipm::Identifier)
    type.index
    type.define_singleton_method(:actual?) { |**args| args.key?(:url) }

    Relaton::Index.pool.instance_variable_get(:@pool)[:BIPM] = type
  end

  config.before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
