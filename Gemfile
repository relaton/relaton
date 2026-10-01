# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# TEMP PIN: the ITU flavor parses every caller reference with `Pubid::Itu`,
# which needs pubid #460 (Radio Regulations, the Operational Bulletin sector
# and date, ITU publication ids like `T-REC-T.4-200307-I`, and `-YYYYMM` read
# as a date). #460 is on pubid `main` but not in the released
# 2.0.0.pre.alpha.13 that both gemspecs require. Remove this pin, and bump
# both gemspecs, once a pubid release carries #460.
#
# The pin is a fixed ref, not `branch: "main"`: `27454393` is the #460 merge,
# the last `main` commit that still parses with parslet. The commits after it
# parse through parsanol PG artifacts, and no published parsanol can load them
# yet (pubid builds against an unreleased local parsanol and does not declare
# it in its gemspec). Move to `main` once pubid depends on a released parsanol.
gem "pubid", path: "/Users/mulgogi/src/pubid/pubid"
gem "parsanol", path: "/Users/mulgogi/src/parsanol/parsanol-ruby"
# TEMP PIN: the v2 instance-driven engine (TODO.cc-citation 07; the
# kinds-based perType from relaton-render#87) is unreleased — the gemspec
# constraint ~> 1.3 resolves the liquid-era 1.3.0, whose engine lacks
# Relaton::Render::Iso690. Remove once a relaton-render release carries
# the v2 engine.
gem "relaton-render", path: "/Users/mulgogi/src/relaton/relaton-render"


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
