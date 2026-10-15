# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# The rawbib fixture expectations reconcile against pubid 2.0.0.pre.alpha.28
# (the stage-word faces: "-YYYY-MM" dates, the D= designator, the glued
# "/V<n>" iteration, pubid#203 — plus the draft-preservation and render
# fixes the ieee IdamsParser fixtures require). alpha.30 additionally
# carries the Pubid::Evs identifiers the relaton/evs flavor parses, the
# evs/cen ETSI and TS faces, the IEEE REV/draft-date identity, and since
# alpha.31 the corrigendum-draft reorder with glued -yyyy-mm dates
# (pubid#529-#532) and the joint IEEE/CSA draft-date glue (#533/#534).
# The gemspec floor follows.
gem "pubid", "2.0.0.pre.alpha.31"

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
  gem "moxml", ">= 0.5.113" # lutaml/moxml#336: the formattedref add_child TypeError fixed in 0.5.113 (relaton#254)
gem "simplecov"
  gem "timecop"
  gem "vcr"
  gem "webmock"
  gem "webrick"
end
# VERIFIED 2026-10-16: leptris 1.9.366.0 + moxml 0.5.138 pass the full
# monorepo suite — 366 ships per-minor native bundles (the ruby-4.0
# native-load failure, leptris#1738) and supersedes 362's prefix
# predeclaration with the Sanitizer behavior intact (leptris#1733).
gem "leptris", "1.9.366.0"
