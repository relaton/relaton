# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Consume the pubid prefixes API (Pubid.prefixes / Pubid::<Flavor>.prefixes) from
# its feature branch until it lands in a released pubid. Once pubid releases the
# API, drop this line and bump the gemspec `pubid` pin instead. (relaton-db#103)
gem "pubid", git: "https://github.com/metanorma/pubid.git",
             branch: "feat/flavor-prefixes-api"

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
