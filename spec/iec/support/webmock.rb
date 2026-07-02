require "webmock/rspec"
require "zip"
require "tmpdir"

INDEX_ZIP_PATH = File.join(__dir__, "..", "fixtures", "index-v2.zip")

RSpec.configure do |config|
  config.before(:suite) do
    yaml = Zip::File.open(INDEX_ZIP_PATH) do |zip|
      zip.first.get_input_stream.read
    end
    # Go through the real read path (write file -> Type#index -> deserialize_pubid)
    # so the index is sorted and `@file_io.sorted` is set: that enables binary
    # search narrowing in Type#search. Setting `@index` directly (as before)
    # left it unsorted, forcing a full O(n) scan of all rows on every search.
    index_file = File.join(Dir.mktmpdir("relaton-iec-spec"), "index-v2.yaml")
    File.write(index_file, yaml)

    type = Relaton::Index::Type.new(:IEC, nil, index_file, nil, ::Pubid::Iec::Identifier)
    type.index # force the offline read + deserialize + sort now, before net is blocked
    # Always treat this pooled index as current. DataFetcher#index calls
    # `find_or_create(:iec, ...)` WITHOUT a :url, and `Pool#type` upcases the
    # key to :IEC — so a url-gated `actual?` returned false there and replaced
    # this pre-sorted index with a fresh Type that re-reads all 32k rows on the
    # next search. That re-read happened repeatedly and dominated the suite
    # (~10x slower). Returning true keeps the one prepared index in the pool.
    type.define_singleton_method(:actual?) { |**| true }

    Relaton::Index.pool.instance_variable_get(:@pool)[:IEC] = type
  end

  config.before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
