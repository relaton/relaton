require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "vcr_cassettes"
  config.default_cassette_options = {
    clean_outdated_http_interactions: true,
    re_record_interval: nil, # deliberate re-record only; auto-rerecord made CI hit unreachable live hosts
    record: :once,
    match_requests_on: %i[method body],
  }
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.filter_sensitive_data("<UN_AUTH_TOKEN>") do |interaction|
    interaction.request.headers["Authorization"]&.first
  end
end
