require "webmock/rspec"
require "zip"
require "tmpdir"

INDEX_ZIP_PATH = File.join(__dir__, "..", "fixtures", "index-v2.zip")

RSpec.configure do |config|
  config.before(:suite) do
    yaml = Zip::File.open(INDEX_ZIP_PATH) do |zip|
      zip.first.get_input_stream.read
    end
    index_file = File.join(Dir.mktmpdir("relaton-jis-spec"), "index-v2.yaml")
    File.write(index_file, yaml)

    type = Relaton::Index::Type.new(:jis, nil, index_file, nil, ::Pubid::Jis::Identifier)
    type.index # force the offline read + deserialize now, before net is blocked
    type.define_singleton_method(:actual?) { |**args| args.key?(:url) }

    Relaton::Index.pool.instance_variable_get(:@pool)[:JIS] = type
  end

  config.before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
