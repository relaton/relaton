# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
the EASC flavor. It is a dev doc — excluded from the packaged gem via the
gemspec `files` glob.

## What this flavor is

`Relaton::Easc` retrieves **EASC** (Eurasian Economic Standards Council; the
Cyrillic МГС council) publications using the Relaton model. It
is **index-backed** (no scraping): it searches a pre-built index via
`Relaton::Index` and fetches per-document YAML from the
`relaton/relaton-data-easc` GitHub repo. Reference parsing uses
`Pubid::Easc::Identifier`.

Two document series, both issued by EASC and catalogued on **mgscatalog.by**:

- **ПМГ** (`pmg`) — Правила по межгосударственной стандартизации (interstate
  standardization *rules*), e.g. `ПМГ 03-2025`, plus the defense variant
  `ПМГ В 31-2001`.
- **РМГ** (`rmg`) — Рекомендации по межгосударственной стандартизации
  (interstate standardization *recommendations*), e.g. `РМГ 151-2025`.

## Architecture

Namespace: `Relaton::Easc`. Retrieval flow:

1. **Bibliography** (`lib/relaton/easc/bibliography.rb`) — `get(code, year)` /
   `search`; parses the reference with `Pubid::Easc.parse`, narrows the index by
   number, fetches the matching YAML over `Net::HTTP`, and returns
   `Item.from_yaml` (an `ItemData`), stamping `fetched`. EASC citations are
   always dated (`ПМГ 03-2025`), so — unlike ISO/OIML — there is no
   undated/most-recent handling; `get` just returns what `search` resolves.
   `ENDPOINT` is the `relaton-data-easc/main` raw base; `INDEXFILE` (`index-v2`)
   is defined in `lib/relaton/easc.rb`.
2. **Index keying** — `Relaton::Index.find_or_create(:easc, url: ...,
   pubid_class: ::Pubid::Easc::Identifier)`. `Pubid::Easc` (from
   `metanorma/pubid`) parses both the Cyrillic surface forms and the Latin
   transliterations (`PMG`/`RMG`/`V`) and renders canonical Cyrillic; its
   attributes are `series` (`"PMG"|"RMG"`, Latin-canonical), `variant`
   (`"V"|nil` — the «В» defense marker), `number`, `year`, and it serializes to
   `_type: pubid:easc:{pmg,rmg}`. `Bibliography#pubid_match?` matches on
   series + variant + number (nil-tolerant year), so ПМГ never matches РМГ and
   the «В» variant never matches the plain series.
3. **Item / ItemData / Ext** (`item.rb`, `item_data.rb`, `ext.rb`,
   `item_base.rb`, `bibitem.rb`, `bibdata.rb`) — `Item` extends `Bib::Item`
   with the typed `Ext` subclass; `Bibitem`/`Bibdata` alias it. `Ext` carries
   the EASC-specific fields so they round-trip natively through both XML and
   YAML (no per-repo merge hacks): `urn` (`urn:easc:<series>:...`), `webpage`
   (mgscatalog.by detail URL), `session` (adopting МГС council session, e.g.
   `67МГС`), `developer` (Разработчик), `joining_states` (collection of country
   codes, e.g. `%w[АРМ БЕИ КАЗ]`), and `assigned_to` (Закреплен за).
4. **Docidentifier** (`docidentifier.rb`) — a plain `Bib::Docidentifier`
   subclass; the `content` is the canonical Cyrillic citation (`ПМГ 03-2025`).
   Subclassed so future `#pubid` integration can hook in without changing the
   public interface.
5. **Doctype** (`doctype.rb`) — `TYPES = %w[pmg rmg]`.
6. **Processor** (`lib/relaton/easc/processor.rb`) — registry integration;
   `@prefix = "EASC"`, `@idtype = "EASC"`, and `@defaultprefix =
   %r{^(?:ПМГ|РМГ|PMG|RMG)\b}` routes **both** Cyrillic and Latin series
   prefixes here. `get` delegates to `Bibliography.get`. Per the lazy-registry
   invariant, each method `require_relative "../easc"` before touching a flavor
   constant, including `remove_index_file`.

There are no scrapers — everything comes from the curated index + GitHub YAML.

## Grammar (upstream, not yet present)

The RelaxNG schemas in the repo-root `grammar/` are **copies of the upstream
source of truth** `metanorma/metanorma-model-iso/grammars/` (authored as `.rnc`,
compiled to `.rng`). There is **no EASC grammar upstream yet**, so this flavor
intentionally ships **no** `grammar/relaton-easc*.rng` and **no** Jing/XML-schema
validation spec. Adding the upstream `relaton-easc.rnc` (extending
`BibDataExtensionType` with the `Ext` elements above, à la the plateau pattern)
is tracked as a cross-project hand-off to metanorma-model-iso; once it lands,
copy the compiled pair into `grammar/` and add the round-trip Jing spec.

## Testing

RSpec + WebMock. `spec/easc/support/webmock.rb` builds an offline `index-v2`
in-memory from `Pubid::Easc` identifiers (so each row round-trips through
`from_hash`/`to_hash` like a published index), preloads it into the
`Relaton::Index` pool in `before(:suite)`, and stubs per-document requests from
`spec/easc/fixtures/data/*.yaml`. No test hits the network. Run with
`bundle exec rake spec:easc`.
