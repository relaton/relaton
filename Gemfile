# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Default group (installed even when the release strips dev/test): the release
# job runs `bundle config without 'development test'` before `bundle exec rake
# build_all`, so rake must live outside those groups or publishing can't run it.
gem "rake"

group :development, :test do
  # XML/YAML canonical comparison matchers for specs. Pinned below 0.3.52:
  # that version adds a dependency on `yeptris`, and `lutaml-model` then picks
  # yeptris as its YAML adapter. Its first model `to_yaml` requires
  # `yeptris/psych`, which replaces `Object#to_yaml` for the whole process. The
  # `---` header is then lost on Linux, and on Windows every `to_yaml` raises
  # `NameError: uninitialized constant Yeptris::FFI::NODE_SCALAR`. Remove the
  # pin when yeptris no longer replaces `Object#to_yaml`.
  gem "canon", "< 0.3.52"
  gem "equivalent-xml"
  gem "pry"            # bin/console
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
