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
# deterministically (pubid#540), and alpha.34 classifies the OMG glued
# catalogue beta label into the version (pubid#548). The raw-Hash dump of
# relaton#272 is gone; the nist suite passes standalone. alpha.35 sheds
# the dotted draft designator's zero padding (pubid#552, the
# 2026-10-19 ruling: "D013.0" -> "D13.0") and rides the stage iteration
# onto the D= face. alpha.36-38 close the track-01 reference-lossiness
# wave: the NIST "Suppl" spelling and the supplement revision fold
# (pubid#553), the IEEE D= designator re-parses in every rendered form
# (pubid#556), and the IEEE-led joint dash/underscore stage aliases
# re-spell as their D= face (pubid#559). alpha.39 re-spells the
# remaining catalogue aliases (pubid#560): the stage-first joint dash
# part with a bare comma year, the glued WD tail, the glued language
# marker, the two-digit draft ordinal and the revision word after the
# draft. The rawbib fixtures for the WD tail and the 11073 draft move
# to the faces this release renders. alpha.40 resolves the draft-stage
# ladder on project-draft aliases (pubid#561): a date-only "Draft Std"
# takes the fabricated D1 stage, and a stage-token draft version
# ("/DCD1") takes that stage. No rawbib expectation moves. alpha.41
# rebuilds the NIST URN payload's part letter, edition additional text
# and addendum markers (pubid#562) — URN ingestion only; no rawbib
# expectation moves. alpha.42 adds the missing revision_of? relational
# predicate and makes dated_version_of?/draft_of? compare exclude lists
# instead of matches?, so they stop raising on NIST's wildcard matches?
# (pubid#563). API addition only; no rawbib expectation moves. alpha.43
# drops the last two require_relative calls in library code (pubid#565,
# autoload only); no rawbib expectation moves. alpha.44 gates every
# shipped PARG artifact on its freshness envelope (pubid#566, spec only);
# no rawbib expectation moves. alpha.45 adds the full-corpus throughput
# benchmark and its release wiring (pubid#567, dev tooling only); no
# rawbib expectation moves. alpha.46 repairs the ISO URN rebuild's
# supplement-family stages and bare languages (pubid#569) — parse_urn
# only; no rawbib expectation moves. alpha.47 makes the ISO
# harmonized-code stage lookup deterministic (pubid#570) — parse_urn
# only; no rawbib expectation moves. alpha.48 is input-side only: the
# IEC stage-alias registrations (ADIS/AWI/DIS/CDISH/CDPAS) with the
# stage-code SSOT extract (pubid#571) and the JCGM dotted supplement
# tolerance (pubid#574, "Amd.1:2026" in, "Amd 1" rendered unchanged) —
# locate_stage lookups and an alternate input form; no rawbib
# expectation moves. alpha.49 completes the IEC stage-code SSOT round
# (pubid#578, registry lookups only). alpha.50 carries YARD docs
# (pubid#579), the NIST index-suffix normalization to its long form
# (pubid#584), the NIST n+UPPER annex-suffix parse (pubid#585) and the
# bare ISO TC reference parse (pubid#583); alpha.51 stops the NIST
# number suffix from consuming the annex token (pubid#586); alpha.52
# wires the ISO RFC 5141-bis additive extension through from_urn onto
# the one URN render path (pubid#587). The NIST suffix pair and the
# ISO URN path are parse/render-side: no rawbib expectation moves, but
# the corpus known_failures reconciliation rides this bump.
# alpha.53-57 close the two-party draft-face wave: the ISO guide-chain
# URN supplement resolution and the docnumber guard (pubid#591), the #582
# D= draft-stage lookup plus the two-party joint routing (pubid#593), the
# printed-joint strip, and the draft-face round-trip convergence
# (pubid#595): the draft reader stores the compact wire form and
# from_hash materializes the runtime components, so rebuilt IEEE rows
# compare equal to their parses.
# alpha.58-59 carry the draft wire-form convergence and the joint /D
# ruling (pubid#598/#602): a joint row carrying a numeric /D designator
# is a draft, and its face carries the word Draft alongside the P
# (pubid#597). The two P24774 rawbib pins move onto the Draft faces.
# alpha.60-62 converge the Draft component and add wrapped_edition_of?
# to the relational vocabulary (pubid#601/#606, pubid#580's ruling): a
# dated base query resolves the wrapped record of that edition. No
# rawbib expectation moves; the retrieval fixture's wrapper case flips.
gem "pubid", "2.0.0.pre.alpha.64"
# parsanol 1.3.114 (ruby#361) carries the numeric capture editions —
# the canonical edition 2 header and the integer envelope field — and
# the edition-2 whitespace-class glue fix; pubid rides it
# (pubid#617 re-bakes every artifact at 1.3.114 and floors the gemspec
# there), so the pin moves with it.
gem "parsanol", "1.3.114"


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
# leptris 1.9.370.1: current line, carries the Ruby 4.0
# memory-allocation fix (leptris#1755) — battery accompanies this bump.
# (leptris#1742) — the battery re-run accompanies this bump.
gem "leptris", "1.9.370.1"

