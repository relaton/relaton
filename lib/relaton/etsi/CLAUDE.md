# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-etsi is a Ruby gem that retrieves ETSI (European Telecommunications Standards Institute) standards metadata using the Relaton bibliographic item model. It fetches data from the ETSI website and the relaton-data-etsi GitHub repository.

## Commands

```bash
# Install dependencies
bin/setup

# Run all tests
rake spec

# Run a specific test file
rspec spec/relaton/etsi/bibliography_spec.rb

# Run a specific test by line number
rspec spec/relaton/etsi/bibliography_spec.rb:15

# Run linter
rake rubocop

# Interactive console
bin/console

# Install gem locally
bundle exec rake install
```

## Architecture

The codebase is transitioning from `RelatonEtsi` namespace to `Relaton::Etsi` namespace.

### New Architecture (lib/relaton/etsi/)

Uses Lutaml for serialization:
- `Item` - base bibliographic item inheriting from `Bib::Item`
- `Bibitem` - for `<bibitem>` XML output (includes `Bib::BibitemShared`)
- `Bibdata` - for `<bibdata>` XML output (includes `Bib::BibdataShared`)
- `Ext` - ETSI-specific extension data (marker, frequency, mandate, custom_collection)
- `Doctype` - ETSI document type with abbreviations (EN, ES, GS, TS, TR, etc.)

### Legacy Architecture (lib/relaton_etsi/)

- `BibliographicItem` - extends `RelatonBib::BibliographicItem`
- `XMLParser` - parses XML into bibliographic items
- `HashConverter` - converts hashes to bibliographic items
- `DocumentType` - document type with type/abbreviation mapping

### Core Components

- `Bibliography` - searches and retrieves standards from relaton-data-etsi index
- `DataFetcher` - fetches all documents from ETSI website CSV export
- `DataParser` - parses CSV rows into bibliographic items
- `Processor` - Relaton processor for integration with the relaton ecosystem

### Data Flow

1. `Bibliography.get(ref)` searches the relaton-data-etsi index
2. Fetches YAML from GitHub, converts to `Item` using `from_yaml`
3. `DataFetcher.fetch` pulls CSV from etsi.org, parses with `DataParser`, saves to output folder

### Pubid-backed index-v2

The ETSI index is **pubid-structured** (`index-v2.yaml`/`.zip`): each row's `:id`
is a `Pubid::Etsi::Identifier` serialized to its `_type: pubid:etsi:{etsi-standard,
amendment,corrigendum}` hash (the whole published ETSI corpus round-trips on the
pinned pubid — see the root `CLAUDE.md` pubid-pin note). The rows use the **flat,
compact** shape (`type`/`number`/`version`/`year`/`month` as scalars under
`_type`) that the published `relaton-data-etsi` index carries — the ETSI
`to_hash` flattening lives on pubid `main` (merged from
`refactor/flatten-etsi-to-hash`), which the root `Gemfile` temporarily pins until
it ships in a pubid release. The wiring mirrors NIST/JCGM:

- **Producer** (`DataFetcher`): `index` calls `find_or_create(:etsi, file:
  INDEX_FILE, pubid_class: ::Pubid::Etsi::Identifiers::Base)`; `#save` parses the
  docid via `#pubid` and stores the **pubid object** (`index.add_or_update pid,
  file`) so `Relaton::Index` sorts by id number and serializes each id to its
  `_type:` hash on save. `#pubid` returns nil (skipping the whole record) for any
  id it can't parse **or** `to_hash`-serialize, so one malformed record can never
  abort the crawl or corrupt the index. (No current ETSI record is skipped.)
- **Consumer** (`Bibliography#search`): parses the reference with
  `::Pubid::Etsi.parse` (via `#parse_pubid`, which returns nil → "not found" for
  an unrecognized ref rather than raising — the ETSI parser wraps failures as
  `RuntimeError`, uncaught by the CLI's `Parslet::ParseFailed` handler), then
  `#best_match` does the ISO-style lookup:
  `index.search(pubid) { |row| pubid.matches?(row[:id], ignore:) }`. The `pubid`
  (not a String) lets `Relaton::Index` narrow candidates by number via binary
  search before the block; `ignore` is the refinements the ref omits
  (`%i[version date]` that are nil) so a bare `ETSI GS ZSM 012` matches every
  edition while a fully-qualified ref matches only its edition; `max_by { row[:id]
  .to_s }` returns the most recent. Requires the ETSI parser to accept partial
  refs (bare number, optional version/date) — on pubid `main`.
  - **Known limitation:** a *part-less* ref (`ETSI EN 300 175`, no `-1`) does not
    match its parts — ETSI pubid keeps the part inside the `code` component, so
    `exclude(:part)` can't drop it without also dropping the number. Refs normally
    carry the part, so this only affects the uncommon all-parts query; closing it
    needs a pubid change (a code-level part exclusion).
- **Processor** `#remove_index_file` passes the same `pubid_class:`.

## Testing

- **Index fixture:** `spec/fixtures/index-v2.zip` (pubid `_type:` rows) is loaded
  into the `Relaton::Index` pool in `before(:suite)` (`spec/support/webmock.rb`):
  the YAML is written to a temp file and read through
  `Relaton::Index::Type.new(:etsi, nil, file, nil, ::Pubid::Etsi::Identifiers::Base)`,
  and `type.index` forces the offline `pubid_class` deserialize before the net is
  blocked; `actual?` is overridden to match only the remote (`url:`) lookup so the
  producer-side `find_or_create(:etsi, file:, pubid_class:)` still gets a fresh
  instance. Regenerate by parsing `index-v1`'s ids through `Pubid::Etsi` into a
  `pubid_class` `Type` and re-zipping (`_type: pubid:etsi:…` rows).
Uses RSpec with VCR for HTTP interaction recording. VCR cassettes are in `spec/vcr_cassettes/`. When tests make new HTTP requests, VCR will record them.
