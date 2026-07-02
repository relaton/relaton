require "webmock/rspec"
require "zip"
require "tmpdir"
require "relaton/iho"

INDEX_ZIP_PATH = File.join(__dir__, "..", "fixtures", "#{Relaton::Iho::INDEXFILE}.zip")

RSpec.configure do |config|
  config.before(:suite) do
    yaml = Zip::File.open(INDEX_ZIP_PATH) do |zip|
      zip.first.get_input_stream.read
    end
    # Type loads from a file path, so extract the fixture zip to an ephemeral
    # temp file (not committed — only the zip is shipped, per `rake update_index`).
    index_file = File.join(Dir.mktmpdir("relaton-iho-spec"), "#{Relaton::Iho::INDEXFILE}.yaml")
    File.write(index_file, yaml)

    # Pass pubid_class so each row's :id is rebuilt into a Pubid::Iho::Identifiers::*
    # via from_hash; force the offline read + deserialize now, before net is blocked.
    type = Relaton::Index::Type.new(:iho, nil, index_file, nil, ::Pubid::Iho::Identifiers::Base)
    type.index
    type.define_singleton_method(:actual?) { |**args| args.key?(:url) }

    Relaton::Index.pool.instance_variable_get(:@pool)[:IHO] = type
  end

  config.before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
