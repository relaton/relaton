require "webmock/rspec"
require "zip"
require "yaml"

INDEX_ZIP_PATH = File.join(__dir__, "..", "fixtures", "index-v2.zip")

RSpec.configure do |config|
  config.before(:suite) do
    yaml = Zip::File.open(INDEX_ZIP_PATH) do |zip|
      zip.first.get_input_stream.read
    end
    index_data = YAML.safe_load(yaml, permitted_classes: [Symbol])
    index_data = index_data.map do |r|
      { id: Pubid::Ccsds::Identifier.from_hash(r[:id]), file: r[:file] }
    end

    type = Relaton::Index::Type.new(:ccsds, nil, "index-v2.yaml")
    type.instance_variable_set(:@index, index_data)
    type.define_singleton_method(:actual?) { |**args| args.key?(:url) }

    Relaton::Index.pool.instance_variable_get(:@pool)[:CCSDS] = type
  end

  config.before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
