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
`to_hash` flattening (merged from `refactor/flatten-etsi-to-hash`) ships in the
released pubid `2.0.0.pre.alpha.13` that the gemspec pins. The wiring mirrors NIST/JCGM:

- **Producer** (`DataFetcher`): `index` calls `find_or_create(:etsi, file:
  "#{INDEXFILE}.yaml", pubid_class: ::Pubid::Etsi::Identifier)`; `#save` parses the
  docid via `#pubid` and stores the **pubid object** (`index.add_or_update pid,
  file`) so `Relaton::Index` sorts by id number and serializes each id to its
  `_type:` hash on save. `#pubid` returns nil (skipping the whole record) for any
  id it can't parse **or** `to_hash`-serialize, so one malformed record can never
  abort the crawl or corrupt the index. (No current ETSI record is skipped.)
- **Consumer** (`Bibliography#search`): parses the reference with
  `::Pubid::Etsi.parse` and lets a `Pubid::Errors::ParseError` on an unrecognized ref
  **propagate** (ISO parity — the CLI renders a friendly message, API callers
  rescue it), then `#best_match` selects with pubid's subset match
  `pubid === row`. The `pubid` (not a String) lets `Relaton::Index` narrow
  candidates by number via binary search. A `version` or `date` that the ref
  omits matches any value, so a bare `ETSI GS ZSM 012` matches every edition
  and a fully-qualified ref matches only its edition.
  `max_by { edition_key(row[:id]) }` returns the most recent.
  Requires pubid `main` (partial-ref parsing, `Pubid::Errors::ParseError` on
  failure, `subset_strict`).
- **A part-less reference strips the ROW's parts, it does not ask pubid for
  "all parts".** pubid declares `parts` strict for ETSI (pubid#408), so a
  part-less ref matches no part row on its own. `#comparable` therefore
  matches each row without its parts (`exclude(:part, :subpart, :parts)`, a
  copy — the cached index id is untouched), and `ETSI EN 300 175` reaches its
  16 part rows. **Do not use `#to_all_parts` here.** Since pubid#433 "all
  parts" is a class, and `Pubid::AllPartsIdentifier#===` compares the document
  alone: it drops the version and the date as well, so
  `ETSI GR ZSM 011 V1.1.1 (2023-02)` answered with V2.1.1 (2024-09) — 586,487
  pairs over the fixture. `resolves a fully-qualified part-less reference to
  that exact edition` in `bibliography_spec.rb` pins it.
- **A base reference does not reach its supplements.** `===` requires the
  same class, so `ETSI ETR 310` does not match the corrigendum
  `ETSI ETR 310/C1`, and a corrigendum of the base (`ETS 300 092-1/C1`) does
  not match a corrigendum of its amendment (`092-1/A1/C1`). The
  `matches?(…, ignore:)` it replaced did match them: over the 28,651-row
  fixture, 298 pairs changed, all of them a supplement row that the old match
  let in, and 218 of 94,079 references resolved to a newer amendment or
  corrigendum instead of the document itself (`ETSI ETR 310` →
  `ETR 310/C1 ed.1 (1996-10)`). `bibliography_spec.rb` pins that case.
- **`#edition_key` orders on the parsed version, never on the rendered id.** ETSI
  versions are not zero-padded, so a String comparison of `row[:id].to_s` orders
  `V9.0.0` above `V19.0.0` and `ed.9` above `ed.11` — it picked the wrong edition
  for 983 of the 3007 multi-edition documents in the spec fixture, and a bare
  `ETSI TR 155 919` resolved to the 2010 edition. `Pubid::Etsi::Identifier` is
  **not** `Comparable` (its `<=>` returns nil), so the key is built from the
  components: `id.version.version` holds the bare numbers (`"19.0.0"`, or `"9"`
  for the `ed.N` form) and `id.date` renders as `yyyy-mm` for the tie-break.
  Both delegate to `base` on a `pubid:etsi:corrigendum`/`amendment` row (162 of
  them in the fixture), so every row shape keys the same way. The key ignores
  `is_edition`, which puts `ed.11` above `V1.0.0` — safe because **no** document
  mixes the two forms (measured: 0 of 28651 fixture rows). Do not put `.to_s`
  back.
- **Processor** `#remove_index_file` passes `url: true` and `file:` only. It
  needs no `pubid_class:`: the delete never reads the index (see
  `lib/relaton/index/CLAUDE.md`).

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
across the whole corpus. This flavor picks the newest edition (`#best_match`
orders on `#edition_key`). Also check the crawl against the 6-hour GitHub
Actions job cap — it roughly doubles — and confirm all three EN 319 142-1
editions land in `data/` before merging the re-crawl.

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
