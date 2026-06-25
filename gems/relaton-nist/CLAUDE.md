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
- `DataFetcher` < `Core::DataFetcher` — fetches NIST Tech Pubs MODS XML from GitHub releases
- `ModsParser` — maps MODS XML (via `loc_mods`) to `ItemData`
- `Scraper` — fetches items from GitHub YAML or CSRC JSON
- `PubsExport` — singleton; caches CSRC pubs-export zip with thread-safe daily updates

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

Tests use VCR with WebMock. Cassettes are stored in `spec/vcr_cassettes/` and re-record every 7 days.

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
