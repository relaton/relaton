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
# alpha.32 casts the NIST from_hash number through the number component
# deterministically (pubid#540) — the order-dependent raw-Hash dump of
# relaton#272 is gone; the nist suite passes standalone.
gem "pubid", "2.0.0.pre.alpha.32"

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
# leptris 1.9.362.1 rebuilds the 362 line with the namespace-cache fix
# (leptris#1742) — the battery re-run accompanies this bump.
gem "leptris", "1.9.362.1"
