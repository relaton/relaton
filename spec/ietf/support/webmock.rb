require "webmock/rspec"
require "zip"
require "yaml"
require "pubid"
require "pubid/ietf"

# The combined index published by relaton-data-ietf, copied wholesale rather than
# curated: a subset goes stale against the live data repo and surfaces as a 404 on
# the document fetch, which reads like a code bug. Refresh by re-downloading
# `index-v2.zip` from that repo.
IETF_INDEX_ZIP_PATH = File.join(__dir__, "..", "fixtures", "ietf-index-v2.zip")

RSpec.configure do |config|
  # Pre-load the index into the pool once for the whole suite, so no example
  # downloads it. Deserialising ~177k pubid ids is not free, hence before(:suite).
  config.before(:suite) do
    yaml = Zip::File.open(IETF_INDEX_ZIP_PATH) do |zip|
      zip.first.get_input_stream.read
    end

    # Mirror what FileIO does on a real load: rows carry *deserialised* pubid
    # objects, sorted by the narrowing key. Both matter — raw hashes would make
    # every lookup miss, and leaving `sorted` false disables the bsearch, which
    # against 177k rows is the difference between microseconds and ~40 seconds
    # per lookup.
    rows = YAML.safe_load(yaml, permitted_classes: [Symbol]).map do |row|
      { id: ::Pubid::Ietf::Identifier.from_hash(row[:id]), file: row[:file] }
    end
    rows.sort_by! { |r| r[:id].root.number.to_s }

    type = Relaton::Index::Type.new(:IETF, nil, "index-v2.yaml", nil,
                                    ::Pubid::Ietf::Identifier)
    type.instance_variable_set(:@index, rows)
    type.instance_variable_get(:@file_io).sorted = true
    type.define_singleton_method(:actual?) { |**args| args.key?(:url) }

    Relaton::Index.pool.instance_variable_get(:@pool)[:IETF] = type
  end

  config.before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
