# frozen_string_literal: true

# require "bundler/setup"
require "fileutils"
require "rspec/matchers"
require "equivalent-xml"
require "simplecov"
require "vcr"

VCR.configure do |c|
  c.cassette_library_dir = "vcr_cassetes"
  c.default_cassette_options = {
    clean_outdated_http_interactions: true,
    re_record_interval: 7 * 24 * 3600,
    record: :once,
    allow_playback_repeats: true,
    preserve_exact_body_bytes: true,
  }
  c.hook_into :webmock
  c.configure_rspec_metadata!
end

SimpleCov.start do
  add_filter "/spec/"
end

require "relaton/db"

# The registry loads flavors lazily in production (see lazy_loading_spec.rb):
# it requires only each flavor's processor file, not its heavy top-level. But
# umbrella specs reference flavor constants directly (Relaton::Iso::ItemData,
# Relaton::Nist::Bibliography, ...), so eager-load every flavor here to keep
# the suite order-independent. Test process only; production stays lazy.
Relaton::Db::Registry::SUPPORTED_GEMS.each do |b|
  require b
rescue LoadError
  # flavor gem not present in this environment — skip it
end

Relaton::Db.configure do |config|
  config.use_api = false
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.expose_dsl_globally = true
end
