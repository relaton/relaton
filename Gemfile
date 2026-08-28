# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# TEMP PIN: the `jcgm`, `bipm`, `etsi`, `cie`, `itu`, `ieee`, `iana` and `ietf`
# flavors need pubid support not yet in the released 2.0.0.pre.alpha.8 that
# relaton.gemspec pins:
#   - JCGM: meetings, bare GUM/VIM-N guides, the Corrigendum suffix, and the
#     flattened compact `to_hash`.
#   - BIPM: the whole `Pubid::Bipm` grammar (committee documents, meetings,
#     Metrologia articles, SI Brochure) that the migrated flavor uses to build and
#     read its pubid `index-v2` (`_type: pubid:bipm:*`); see lib/relaton/bipm.
#   - ETSI: the flattened compact `to_hash` (`_type: pubid:etsi:*` with scalar
#     type/number/version/year/month) that the published `relaton-data-etsi`
#     index-v2 carries (the older nested shape can't deserialize it).
#   - CIE: proceedings ids (`_type: pubid:cie:proceedings` with paper/page_range),
#     techstreet variant parsing, and the flattened compact `to_hash` that the
#     published `relaton-data-cie` index-v2 carries.
#   - ITU: `Pubid::Itu` handbook/question identifier types plus the flattened
#     compact ITU `to_hash` (scalar sector/series/number/parts, e.g.
#     `_type: pubid:itu:handbook`) that the published `relaton-data-itu-r` index-v2
#     carries (the older nested shape can't deserialize it); and pubid #325, which
#     parses the ITU-T print forms (`Technical Cor.`, Appendices, `bis`/`ter`, the
#     D-series `R` suffix, series supplements, joint numbering, `Add. N`, bare
#     `v10`/`V2`/`v.1` versions) that 702 published records use — without it those
#     records index only if relaton rewrites their docids, which it no longer does.
#   - IEEE: the full IEEE identifier work (historical formats, draft-verbatim,
#     redline, numbered/letter revision, edition, trademark rendering, update_codes
#     one-offs) that lets `relaton-data-ieee` migrate to a pubid `index-v2` and
#     `RawbibIdParser` go pubid-first (`_type: pubid:ieee:*`).
#   - IANA: `Pubid::Iana::Identifiers::Registry#number` (the top-level registry
#     slug). Before it, `Registry` set no `number` at all, so `id.root.number.to_s`
#     — the key `Relaton::Index::Type#candidates_by_number` bsearches on — was ""
#     for all 3405 published rows. An IANA `index-v2` was therefore impossible:
#     every row would have landed in one bucket and the bsearch degraded to a
#     linear scan, silently. See lib/relaton/iana.
#   - IETF: the whole `Pubid::Ietf` flavor (added 2026-07-15, after alpha.8), plus
#     three fixes landed 2026-08-20 for relaton#109 — draft slugs containing `.`
#     or uppercase, zero-padded sub-series (`STD0066` → `STD 66`), and the draft
#     slug living in `number` so the index bsearch key is non-empty. The last is
#     the same trap IANA hit above, in a different flavor.
#     `spec/ietf/relaton/ietf/pubid_contract_spec.rb` fails without them.
#   - W3C: `Pubid::W3c::Identifier` stored the document slug in `code` and never
#     set the `number` it inherits, so every index row keyed on `""` and
#     `Relaton::Index::Type#candidates_by_number` degraded to a linear scan over
#     the whole index, silently. pubid #339 renames the attribute `code` ->
#     `number`, with NO alias reader; `Relaton::W3c::Docidentifier` and the
#     `index-v2` this gem now writes both read `number`.
# All live on pubid `main`, which also carries the `base_identifier` -> `base`
# accessor/serialization-key rename (pubid #139) that relaton adopts here: pubid
# removed `.base_identifier` with no alias, and `#root` now reaches the origin for
# every flavor (the index narrowing key relies on it). main is the SAME pubid that
# built the published relaton-data-{jcgm,etsi,cie,itu-r,ieee} indexes, so those
# flavors can deserialize them. main also DROPPED the redundant
# `Pubid::<Flavor>::Identifiers::Base` alias from the Category-A flavors (iho,
# etsi, ...); relaton now names the canonical `Pubid::<Flavor>::Identifier`
# deserialization root, so the old alias would NameError at IHO/ETSI index load.
# TODO: revert to the released pubid once these changes ship in a pubid release.
gem "pubid", git: "https://github.com/metanorma/pubid.git", branch: "main"

# Default group (installed even when the release strips dev/test): the release
# job runs `bundle config without 'development test'` before `bundle exec rake
# build_all`, so rake must live outside those groups or publishing can't run it.
gem "rake"

group :development, :test do
  gem "canon"          # XML/YAML canonical comparison matchers for specs
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
