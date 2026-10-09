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

  # Ignore index download requests — handled by a global WebMock stub instead
  config.ignore_request do |request|
    URI(request.uri).path.end_with?("index-v2.zip")
  end
end
