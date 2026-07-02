# frozen_string_literal: true

# Umbrella (Relaton::Db) suite setup — auto-loaded by the shared spec_helper
# only when CWD is spec/relaton/. Moved here from the former per-suite
# spec_helper so all suites can share one helper.

require "fileutils"
require "vcr"

VCR.configure do |c|
  c.cassette_library_dir = "vcr_cassetes" # (sic) matches this suite's cassette dir
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

require "relaton/db"

# The registry loads flavors lazily in production (see lazy_loading_spec.rb): it
# requires only each flavor's processor file, not its heavy top-level. But
# umbrella specs reference flavor constants directly (Relaton::Iso::ItemData,
# Relaton::Nist::Bibliography, ...), so eager-load every flavor here to keep the
# suite order-independent. Test process only; production stays lazy.
Relaton::Db::Registry::SUPPORTED_GEMS.each do |b|
  require b
rescue LoadError
  # flavor gem not present in this environment — skip it
end

Relaton::Db.configure do |config|
  config.use_api = false
end
