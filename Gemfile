# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# The rawbib fixture expectations reconcile against pubid 2.0.0.pre.alpha.28
# (the stage-word faces: "-YYYY-MM" dates, the D= designator, the glued
# "/V<n>" iteration, pubid#203 — plus the draft-preservation and render
# fixes the ieee IdamsParser fixtures require). The gemspec floor follows.
gem "pubid", "2.0.0.pre.alpha.28"

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
  gem "moxml", ">= 0.5.113" # lutaml/moxml#336: the formattedref add_child TypeError fixed in 0.5.113 (relaton#254)
gem "simplecov"
  gem "timecop"
  gem "vcr"
  gem "webmock"
  gem "webrick"
end
# VERIFIED 2026-10-09: leptris 1.9.323.0 + moxml 0.5.120 +
# lutaml-model 0.8.97 pass the full relaton-cli suite (262/0, the
# relaton_file_spec add_child TypeError site) and match the 1.9.312
# line across the relaton/bsi/jis/plateau suites; floor at the
# verified line so fixes flow
gem "leptris", ">= 1.9.323.0"
