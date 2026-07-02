require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "vcr_cassettes"
  config.default_cassette_options = {
    clean_outdated_http_interactions: true,
    re_record_interval: 7 * 24 * 3600,
    record: :once,
  }
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Index downloads are handled by pre-loaded fixtures in webmock.rb
  config.ignore_request do |request|
    URI(request.uri).path.end_with?("index-v2.zip")
  end
end
