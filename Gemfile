# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# TEMP PIN: the `jcgm`, `etsi`, `cie`, `itu` and `ieee` flavors need pubid support
# not yet in the released 2.0.0.pre.alpha.8 that relaton.gemspec pins:
#   - JCGM: meetings, bare GUM/VIM-N guides, the Corrigendum suffix, and the
#     flattened compact `to_hash`.
#   - ETSI: the flattened compact `to_hash` (`_type: pubid:etsi:*` with scalar
#     type/number/version/year/month) that the published `relaton-data-etsi`
#     index-v2 carries (the older nested shape can't deserialize it).
#   - CIE: proceedings ids (`_type: pubid:cie:proceedings` with paper/page_range),
#     techstreet variant parsing, and the flattened compact `to_hash` that the
#     published `relaton-data-cie` index-v2 carries.
#   - ITU: `Pubid::Itu` handbook/question identifier types plus the flattened
#     compact ITU `to_hash` (scalar sector/series/number/parts, e.g.
#     `_type: pubid:itu:handbook`) that the published `relaton-data-itu-r` index-v2
#     carries (the older nested shape can't deserialize it).
#   - IEEE: the full IEEE identifier work (historical formats, draft-verbatim,
#     redline, numbered/letter revision, edition, trademark rendering, update_codes
#     one-offs) that lets `relaton-data-ieee` migrate to a pubid `index-v2` and
#     `RawbibIdParser` go pubid-first (`_type: pubid:ieee:*`).
# All live on pubid `main`, which also carries the `base_identifier` → `base`
# accessor/serialization-key rename (pubid #139) that relaton adopts here: pubid
# removed `.base_identifier` with no alias, and `#root` now reaches the origin for
# every flavor (the index narrowing key relies on it). main is the SAME pubid that
# built the published relaton-data-{jcgm,etsi,cie,itu-r,ieee} indexes, so those
# flavors can deserialize them. main also DROPPED the redundant
# `Pubid::<Flavor>::Identifiers::Base` alias from the Category-A flavors (iho,
# etsi, …); relaton now names the canonical `Pubid::<Flavor>::Identifier`
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
