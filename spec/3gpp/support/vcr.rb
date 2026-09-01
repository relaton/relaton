require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "vcr_cassettes"
  config.default_cassette_options = {
    clean_outdated_http_interactions: true,
    re_record_interval: 7 * 24 * 3600,
    record: :once,
    preserve_exact_body_bytes: true,
  }
  config.hook_into :webmock

  # Index downloads are handled by pre-loaded fixtures in webmock.rb. Matched
  # on the version-agnostic name so the next INDEXFILE bump does not silently
  # start recording index downloads into cassettes.
  config.ignore_request do |request|
    URI(request.uri).path.match?(%r{/index-v\d+\.zip\z})
  end
end
