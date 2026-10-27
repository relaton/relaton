require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "vcr_cassettes"
  config.default_cassette_options = {
    clean_outdated_http_interactions: true,
    re_record_interval: nil, # deliberate re-record only; auto-rerecord made CI hit unreachable live hosts
    record: :once,
    preserve_exact_body_bytes: true,
  }
  config.hook_into :webmock
  config.configure_rspec_metadata!
  $ignore_pubs_export = true # rubocop:disable Style/GlobalVars
  config.ignore_request do |request|
    path = URI(request.uri).path
    path.end_with?("index-v2.zip") || (path.include?("pubs-export") && $ignore_pubs_export) || # rubocop:disable Style/GlobalVars
      # The Pages machine index is the lookup under test (relaton#152):
      # the consumer resolves through the deployed manifest + monolith,
      # so the fetch is live like the zip fetch above it.
      path.end_with?("manifest.json") || path.include?("/index/shard-")
  end
end
