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
  "#{INDEXFILE}.yaml", pubid_class: ::Pubid::Etsi::Identifier)`; `#save` parses the
  docid via `#pubid` and stores the **pubid object** (`index.add_or_update pid,
  file`) so `Relaton::Index` sorts by id number and serializes each id to its
  `_type:` hash on save. `#pubid` returns nil (skipping the whole record) for any
  id it can't parse **or** `to_hash`-serialize, so one malformed record can never
  abort the crawl or corrupt the index. (No current ETSI record is skipped.)
- **Consumer** (`Bibliography#search`): parses the reference with
  `::Pubid::Etsi.parse` and lets a `Parslet::ParseFailed` on an unrecognized ref
  **propagate** (ISO parity — the CLI renders a friendly message, API callers
  rescue it), then `#best_match` does the ISO-style lookup:
  `index.search(pubid) { |row| pubid.matches?(row[:id], ignore:) }`. The `pubid`
  (not a String) lets `Relaton::Index` narrow candidates by number via binary
  search before the block; `ignore` is the refinements the ref omits — `version`
  /`date` when nil, and `:part` when `pubid.code.parts` is empty — so a bare
  `ETSI GS ZSM 012` matches every edition, a part-less `ETSI EN 300 175` matches
  every part, and a fully-qualified ref matches only its edition; `max_by
  { row[:id].to_s }` returns the most recent. Requires pubid `main` (partial-ref
  parsing, `Parslet::ParseFailed` on failure, and part exclusion inside `code`).
- **Processor** `#remove_index_file` passes the same `pubid_class:`.

### The crawl query keeps superseded editions (`version=1`)

`DataFetcher::SOURCEURL` is the ETSI standards-search query, and
`relaton-data-etsi/data/` is **exactly** what it returns — `crawler.rb` rebuilds
`data/` on every run, so a record the query drops cannot be reinstated in the
data repo. The `version` flag selects editions, not statuses: `version=0`
returns only the current edition of each branch, `version=1` returns the
superseded ones as well. The status flags (`withdrawn`, `historical`,
`superseded`, `onApproval`, `isCurrent`) are a **separate axis** and are already
all `1` — that is why the dataset carried `Historical` and `Withdrawn` documents
while still missing older editions (metanorma/metanorma-pdfa#95, which wanted
`ETSI EN 319 142-1 V1.2.1 (2024-01)` back). `version=0` also still returns
parallel current branches, so the response's own `superseded`/`new_versions`
fields, not the major version, are what `version` keys on.

The flavor uses `version=1`. Measured against the live API on 2026-08-27:

| | `version=0` | `version=1` |
|---|---|---|
| records | 28625 | 67446 (2.36x) |
| pages at 50/page | 573 | 1349 |
| `data/` on disk | 112 MB | ~264 MB |
| `index-v2.yaml` | 5.0 MB | ~11.8 MB |

Nothing else in the producer needed changing: the version is part of the ETSI
docid, so `Core::DataFetcher#unique_output_file` gives each edition its own
filename and `Index::Type#add_or_update` (keyed on `id.to_s`) gives each its own
row. `spec/etsi/relaton/etsi/data_fetcher_spec.rb` pins the query flag, and pins
that machinery too — it was already correct, but `version=1` is what makes
several editions of one document a common case rather than a rare one.

**Ordering rule for the data repo.** This is producer-side only; nothing changes
for users until `relaton-data-etsi` re-crawls. Do **not** deploy a `version=1`
crawl until the released `relaton-etsi` gem picks the newest edition. Its
`Bibliography#search` uses `min_by` on the rendered id, which returns the
**oldest** match, so a bare `ETSI EN 319 401` would resolve to the 2013 edition
across the whole corpus. This flavor is already correct (`#best_match` uses
`max_by`). Also check the crawl against the 6-hour GitHub Actions job cap — it
roughly doubles — and confirm all three EN 319 142-1 editions land in `data/`
before merging the re-crawl.

## Testing

- **Index fixture:** `spec/fixtures/index-v2.zip` (pubid `_type:` rows) is loaded
  into the `Relaton::Index` pool in `before(:suite)` (`spec/support/webmock.rb`):
  the YAML is written to a temp file and read through
  `Relaton::Index::Type.new(:etsi, nil, file, nil, ::Pubid::Etsi::Identifier)`,
  and `type.index` forces the offline `pubid_class` deserialize before the net is
  blocked; `actual?` is overridden to match only the remote (`url:`) lookup so the
  producer-side `find_or_create(:etsi, file:, pubid_class:)` still gets a fresh
  instance. Regenerate by parsing `index-v1`'s ids through `Pubid::Etsi` into a
  `pubid_class` `Type` and re-zipping (`_type: pubid:etsi:…` rows).
Uses RSpec with VCR for HTTP interaction recording. VCR cassettes are in `spec/vcr_cassettes/`. When tests make new HTTP requests, VCR will record them.
