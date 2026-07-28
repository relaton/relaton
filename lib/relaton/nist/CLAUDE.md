# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-nist is a Ruby gem that retrieves and manages NIST (National Institute of Standards and Technology) bibliographic metadata as part of the Relaton ecosystem. Data sources include the NIST Cybersecurity Resource Center (CSRC) and the NIST Library (MARC21/MODS XML).

## Development Commands

```bash
# Install dependencies
bundle install

# Run all tests (any of these)
rake
rake spec
bundle exec rspec

# Run a single test file
bundle exec rspec spec/relaton/nist/item_spec.rb

# Run a specific test by line number
bundle exec rspec spec/relaton/nist/item_spec.rb:10

# Interactive console with gem loaded
bin/console

# Lint (uses Ribose OSS rubocop config)
bundle exec rubocop
```

## Architecture

### Module Structure

All classes live under `Relaton::Nist` (entry point: `require 'relaton/nist'`).

### Lutaml-Model Serialization

All data models inherit from `Lutaml::Model::Serializable` and use declarative attribute/mapping DSL for XML and YAML serialization. The base bibliographic types come from `relaton-bib` (aliased as `Bib`).

**Core model hierarchy**:
- `Bib::Item` → `Relaton::Nist::Item` (`model ItemData`)
  - `Relaton::Nist::Bibitem` (includes `Bib::BibitemShared`)
  - `Relaton::Nist::Bibdata` (includes `Bib::BibdataShared`)
- `Bib::ItemData` → `Relaton::Nist::ItemData`

**NIST-specific extensions** (under `lib/relaton/nist/`):
- `Ext` — extension block holding doctype, comment period (extends `Bib::Ext`)
- `Date` — adds `abandoned` and `superseded` date types (extends `Bib::Date`)
- `Relation` — adds `obsoletedBy`, `supersedes`, `supersededBy` relation types (extends `Bib::Relation`)
- `CommentPeriod` — from/to/extended date ranges (extends `Lutaml::Model::Serializable`)
- `Doctype` — currently only `standard` (extends `Bib::Doctype`)

**Search/retrieval layer** (extends `relaton-core`):
- `Bibliography` — class methods `search(text, year, opts)` and `get(code, year, opts)`
- `HitCollection` < `Core::HitCollection` — searches GitHub index + CSRC JSON
- `Hit` < `Core::Hit` — lazily resolves items via `Scraper`
- `Processor` < `Core::Processor` — Relaton plugin interface (`get`, `fetch_data`, `from_xml`, `from_yaml`)

**Data fetching/parsing**:
- `DataFetcher` < `Core::DataFetcher` — fetches NIST Tech Pubs MODS XML from GitHub releases. `#source_url(source)` builds the download URL: with no tag (nil/blank/`"latest"`) it uses GitHub's `releases/latest/download/allrecords-MODS.xml` redirect, so the `relaton-data-nist` crawler auto-picks up new releases without a gem release; passing a concrete tag (e.g. `"June2026"`) pins that release. The `source` flows from `Core::DataFetcher.fetch(source)` → `#fetch(source)` → `#fetch_tech_pubs(source)` (the crawler workflow's `args` input can supply it).
  - **Per-record resilience (mirrors the ISO flavor).** A single bad record must never abort the crawl. `#write_file` skips (never `id.content`-crashes on) a record whose MODS entry yields **no docidentifier** (e.g. a DOI stored only in `<identifier type="doi">`, which `ModsParser#parse_doi` doesn't read), and records ids that `#pubid` can't parse (new series like `NIST RB`/`NIST CHIPS`) as "not indexed" — the YAML is still written, only the index-v2 entry is skipped. Both classes accumulate in `#failures`; the `#report_errors` override emits each at `:error` (via `#log_error` → `Util.error`), which the shared `Core::DataFetcher` gh_issue machinery turns into one "Error fetching documents" GitHub issue in CI (`GITHUB_REPOSITORY` + `GITHUB_TOKEN`). `#pubid` no longer warns per-failure; reporting is centralized in `#report_errors`.
- `ModsParser` — maps MODS XML (via `loc_mods`) to `ItemData`
- `Scraper` — fetches items from GitHub YAML or CSRC JSON
- `PubsExport` — singleton; caches CSRC pubs-export zip with thread-safe daily updates

### Pubid-backed docidentifier

`Relaton::Nist::Docidentifier` (`docidentifier.rb`, `< Bib::Docidentifier`,
declared flat like the rest of the NIST models) parses its `content` into a
`Pubid::Nist::Identifier` kept in `@pubid`, while the lutaml `content` attribute
stays a plain string for serialization. It implements the base class's abstract
`remove_part!` / `remove_date!` / `to_all_parts!` (plus a NIST `remove_stage!`)
by mutating the pubid graph and re-rendering via `refresh_content!`, so NIST
items no longer raise `NotImplementedError` on the `Bib::ItemData#to_all_parts!`
/ `#remove_date!` paths. It is wired into `item.rb`
(`attribute :docidentifier, Docidentifier, collection: true`) and into
`item_base.rb` (`Nist::ItemBase`, the nested bibitem used inside `Relation`), so
relation cross-reference ids are pubid-backed too — mirroring
`iso/model/item_base.rb` / `iec/model/item_base.rb`. `ModsParser` and `Scraper`
build **every** docid (primary NIST id, DOI, and relation cross-refs) as this
class. Mirrors `lib/relaton/iec/model/docidentifier.rb` and
`lib/relaton/ccsds/model/docidentifier.rb`.

NIST-specific gotchas (why this isn't a straight copy of IEC/CCSDS):

- **Adopt-on-round-trip, not a `type` gate.** A NIST DOI such as
  `NIST.SP.800-162` is itself a valid NIST pubid in dotted MR form whose `:human`
  render is `NIST SP 800-162` — so blindly parsing it would rewrite the DOI.
  `content=` therefore keeps the parsed pubid **only when
  `pubid.to_s(:human) == content`**; otherwise the raw string is preserved.
  A `type == "NIST"` gate looks tempting but breaks: lutaml applies setters in
  attribute-declaration order (`content` before `type`), so on `from_yaml` the
  gate sees `type == nil`, drops the pubid, and the mutators silently no-op on
  YAML-loaded items. The round-trip test is type/order-independent.
- **Uniform collection type.** The `docidentifier` collection is typed
  `Nist::Docidentifier`, and lutaml's **YAML/JSON** serializer strictly rejects a
  parent `Bib::Docidentifier` instance in that slot (`IncorrectModelError`) —
  which would crash the YAML-default `DataFetcher` crawler on nearly every
  DOI-bearing record (XML tolerates it, which is why it hides in XML specs). So
  the DOI is a `Nist::Docidentifier` too (kept raw via the round-trip rule), not
  a `Bib::Docidentifier`.
- **The date lives in the `edition` component.** NIST has no `:date` attribute;
  a year is carried as the edition id (`FIPS 46e1977`) or its trailing
  `additional_text` (`NBS CIRC 11e2.1915`), and the scalar `year`/`edition_year`
  fields are nil on the common parse paths. `remove_date!` clears the scalar
  fields *and* strips a 4-digit-year edition/`additional_text`, while preserving
  numbered editions/revisions (`e2`, `r5`). Dates that ride the `update`
  component (some NBS supplements) are left intact — `update` also encodes
  non-date update codes (`/Upd2`), so stripping it would corrupt identity.
- **No `(all parts)` rendering.** pubid-nist never emits an all-parts marker, so
  `to_all_parts!` sets the `all_parts` flag as an invisible no-op and the
  part-stripped id is the best available rendering, matching IEC/CCSDS.

### Serialization Round-Trip Pattern

Models support `from_xml`/`to_xml` and `from_yaml`/`to_yaml`. Tests verify round-trip fidelity by parsing a fixture, re-serializing, and comparing output to input.

### XML Schema Validation

RNG (Relax NG) schemas in `grammars/` validate XML output. Tests use the `jing` gem:
```ruby
schema = Jing.new("grammars/relaton-nist-compile.rng")
errors = schema.validate(file)
```
`relaton-nist-compile.rng` is the top-level schema that includes `relaton-nist.rng` and `basicdoc.rng`.

### HTTP Recording

Tests use VCR with WebMock. Cassettes are stored in `spec/vcr_cassettes/` and
`spec/support/vcr.rb` sets `record: :once` **with `re_record_interval: 7 days`**.

**Gotcha (this bites periodically):** once a cassette is older than 7 days, the
next run **re-records it from the live network** — so the suite is not truly
deterministic. Two known failure modes when that fires: the NIST GitHub source
data can drift (an author renamed, a `loc.gov` `identifier` dropped) so the
round-tripped XML no longer matches the on-disk `spec/fixtures/*.xml` fixtures;
and any flavor whose upstream throttles the recorder records a bad response.
When cassettes show up mass-modified in `git status` for no code reason, that's
the 7-day re-record firing, not a manual change. To recover: re-record cleanly
(delete the stale cassette, run the spec) and, for the integration fixtures that
compare full XML (`get.xml`, `hit.xml`, `hit_bibitem.xml`), regenerate them
(delete → the spec rewrites them via `File.write … unless File.exist?`).

### Test Data Stubbing

Tests pre-load both the NIST index and CSRC pubs-export data from local fixtures in `before(:suite)` (see `spec/support/webmock.rb`), avoiding all HTTP requests for these data sources. VCR is configured to ignore both `index-v2.zip` and `pubs-export` requests (`spec/support/vcr.rb`).

The gem consumes the **index-v2** index (`INDEXFILE = "index-v2"`): each row's `:id` is a `Pubid::Nist::Identifier` hash (lean `to_hash` form), so `HitCollection#from_ga` narrows candidates by number via binary search before the substring block filter, and stringifies `row[:id].to_s` at the Hit boundary. `spec/fixtures/index-v2.zip` is required for the suite to run (`rake spec:update_index` downloads it from `relaton-data-nist/v2`).

- **Index**: The YAML inside `spec/fixtures/index-v2.zip` is written to a temp file and loaded through `Relaton::Index::Type.new(:nist, nil, file, nil, ::Pubid::Nist::Identifier)`; calling `type.index` forces the offline read + `pubid_class` deserialization (and sort) before net is blocked. The instance is injected into `Relaton::Index.pool`, with `actual?` overridden to match only the remote (`url:`) lookup so the producer-side `find_or_create(:nist, file:, pubid_class:)` still gets a fresh instance. Run `rake spec:update_index` to refresh.
- **PubsExport**: The `PubsExport` singleton's `@data` is set directly from `spec/fixtures/pubs-export.zip`. Run `rake spec:update_pubs_export` to refresh.

To apply the index stubbing pattern to other relaton gems:

1. Add a `spec:update_index` rake task (downloads `index-v2.zip` from the gem's GitHub data repo)
2. Run `rake spec:update_index` to create `spec/fixtures/index-v2.zip`
3. In `spec/support/webmock.rb`: extract the zip's YAML, write it to a temp file, create a `Type` with the flavor's `pubid_class`, call `type.index` to deserialize + sort, override `actual?` to match the remote `url:` lookup, and inject into `Relaton::Index.pool`
4. In `spec/support/vcr.rb`: add `ignore_request` for `index-v2.zip`
5. Remove any `allow_any_instance_of(Relaton::Index::Type)` workarounds from specs

## Key Dependencies

- `relaton-bib` — base bibliographic models and shared mixins
- `relaton-core` — base classes for Processor, HitCollection, Hit, DataFetcher
- `loc_mods` — MODS (Metadata Object Description Schema) XML parsing
- `pubid` — NIST publication ID parsing
- `relaton-index` — index/search utilities
- `mechanize` — HTTP fetching for data sources

## Code Style

RuboCop config inherits from the Ribose OSS style guide. Target Ruby version is 3.1.
