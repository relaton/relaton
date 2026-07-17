# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# TEMP PIN: the `jcgm` and `etsi` flavors need pubid support not yet in the
# released 2.0.0.pre.alpha.8 that relaton.gemspec pins:
#   - JCGM: meetings, bare GUM/VIM-N guides, the Corrigendum suffix, and the
#     flattened compact `to_hash`.
#   - ETSI: the flattened compact `to_hash` (`_type: pubid:etsi:*` with scalar
#     type/number/version/year/month) that the published `relaton-data-etsi`
#     index-v2 carries (the older nested shape can't deserialize it).
# Both live on pubid `main` (the ETSI flattening merged there from
# `refactor/flatten-etsi-to-hash`). This is the SAME pubid that built the
# published relaton-data-{jcgm,etsi} indexes, so the flavors can deserialize
# them. TODO: revert to the released pubid once these changes ship in a pubid
# release.
gem "pubid", git: "https://github.com/metanorma/pubid.git", branch: "main"

# Default group (installed even when the release strips dev/test): the release
# job runs `bundle config without 'development test'` before `bundle exec rake
# build_all`, so rake must live outside those groups or publishing can't run it.
gem "rake"

group :development, :test do
  gem "canon"          # XML/YAML canonical comparison matchers for specs
  gem "equivalent-xml"
  gem "rspec"
  gem "rspec-command"  # relaton-cli acceptance specs
  gem "rspec-html"     # relaton-cli
  gem "ruby-jing"      # RelaxNG schema validation
  gem "simplecov"
  gem "timecop"
  gem "vcr"
  gem "webmock"
  gem "webrick"
end
