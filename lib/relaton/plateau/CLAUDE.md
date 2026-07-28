# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-plateau is a Ruby gem for retrieving and managing bibliographic metadata for Project PLATEAU (Japanese 3D city model standards published by MLIT). It is part of the Relaton ecosystem of bibliographic gems.

## Commands

```bash
# Install dependencies
bundle install

# Run all tests
bundle exec rake spec

# Run a single test file
bundle exec rspec spec/relaton/plateau/bibitem_spec.rb

# Run a specific test by line number
bundle exec rspec spec/relaton/plateau/bibitem_spec.rb:15

# Lint
bundle exec rake rubocop

# Default rake task (runs specs)
bundle exec rake
```

## Architecture

All code lives in `lib/relaton/plateau/`. The gem uses LutaML::Model::Serializable for data modeling with automatic XML/YAML serialization.

### Models
- **Item** (`item.rb`) — base Plateau item extending `Bib::Item`, declares `model ItemData` and adds `ext` attribute
- **ItemData** (`item_data.rb`) — data class extending `Bib::ItemData`, returned by `Item.from_xml`, `Item.from_yaml`, and `Bibliography.get`
- **Bibitem** (`bibitem.rb`) — bibliographic item variant (includes `Bib::BibitemShared`)
- **Bibdata** (`bibdata.rb`) — bibliographic data variant (includes `Bib::BibdataShared`)
- **Ext** (`ext.rb`) — extension element: doctype, subdoctype, flavor, editorialgroup, stagename, filesize, etc.
- **Doctype** (`doctype.rb`) — extends `Bib::Doctype`, valid values: `handbook`, `technical-report`, `annex`

### Retrieval & Data Fetching
- **Bibliography** (`bibliography.rb`) — module with `get(code)` for index-based document retrieval, returns `ItemData`
- **HitCollection** / **Hit** — search the relaton-data-plateau index and fetch YAML documents
- **DataFetcher** (`data_fetcher.rb`) — extends `Core::DataFetcher`, scrapes MLIT JSON APIs for handbooks and technical reports
- **Parser** / **HandbookParser** / **TechnicalReportParser** — parse JSON into `ItemData` objects
- **Processor** (`processor.rb`) — standard Relaton processor plugin (`get`, `from_xml`, `from_yaml`, `fetch_data`, `grammar_hash`)

### Serialization Methods
- `bib.to_xml` — XML (bibitem format)
- `Item.to_yaml(bib)` — YAML (class method)
- `bib.to_rfcxml` — BibXML/RFC XML
- `Item.from_xml(xml)` — parse XML into `ItemData`
- `Item.from_yaml(yaml)` — parse YAML into `ItemData`

### Data Sources
- Handbooks: `https://www.mlit.go.jp/plateau/_next/data/1.3.0/libraries/handbooks.json`
- Technical Reports: `https://www.mlit.go.jp/plateau/_next/data/1.3.0/libraries/technical-reports.json`
- Pre-fetched index: `https://raw.githubusercontent.com/relaton/relaton-data-plateau/v2/` (`HitCollection::ENDPOINT`)

### Pubid-backed index (index-v2)

The index is **pubid-structured** (`_type: pubid:plateau:*` rows), mirroring
NIST/CIE. All three `Relaton::Index.find_or_create` call sites
(`data_fetcher.rb`, `hit_collection.rb`, `processor.rb`) pass
`pubid_class: ::Pubid::Plateau::Identifier`, and `INDEXFILE = "index-v2"`.

**Ids are pubid-canonical.** The parsers emit the form `Pubid::Plateau.parse`
accepts, which also matches the MLIT source:
- Handbook: `PLATEAU Handbook #NN 第X.Y版` (Japanese edition label — the parser
  keeps the source `第X.Y版`; the Latinized `#edition` is retained only for the
  structured `Bib::Edition`/`ext` fields).
- Technical Report: `PLATEAU Technical Report #NN` (**no edition** — pubid TRs
  carry none; the document still has a `1.0` `Bib::Edition`).
- Sub-numbers use a hyphen (`#46-1`), not the source underscore (`#46_1`).

`DataFetcher#save_document` parses the canonical id via `#pubid` (a round-trip
guard: `from_hash(to_hash) == to_hash`) and stores the `Pubid::Plateau::Identifier`
object; unparseable ids are warned and skipped (defensive — the parser already
emits canonical, so nothing is expected to skip).

**Search accepts both forms.** `HitCollection#find` parses the query via `#ref`
(`Pubid::Plateau.parse`, memoized) and matches on **pubid objects**, mirroring the
other pubid flavors (ETSI `matches?`, JCGM `exclude`): an exact edition uses
`row[:id] == ref` (pubid `==` compares type + number + annex + edition); a
family query (`ref.edition.nil?` — an edition-less handbook, or any Technical
Report) uses `ref.matches?(row[:id], ignore: [:edition])`. This keeps the
family-vs-exact decision and the match on the *same* parsed identifier (no raw
`@ref` regex). Canonical (`第1.0版`), edition-less (`#00`), and **legacy Latin**
(`#00 1.0`) references all resolve — `Pubid::Plateau` normalizes Latin input to
the canonical id (metanorma/pubid #269; needs the pubid `main` pin). No
relaton-side Latin shim exists by design.

`EDITION_SUFFIX` is **not** used for matching; it lives only in `#to_all_editions`,
which strips the edition off the fetched document's `Bib::Docidentifier`/docnumber
**strings** (relaton-bib content, not pubid) to build the family record — it
matches both Japanese and Latin suffixes so it works against the current (Latin)
VCR-cassette documents and future canonical ones.

### Schema Validation
RNG grammar files in `grammars/` define the XML schema. Tests validate fixtures against `relaton-plateau-compile.rng` using the `ruby-jing` gem.

## Testing

- **Index fixture:** `spec/fixtures/index-v2.zip` (pubid-backed, `_type: pubid:plateau:*` rows) is pre-loaded into the `Relaton::Index` pool in `before(:suite)` via a `Relaton::Index::Type` built with `::Pubid::Plateau::Identifier` (configured in `spec/support/webmock.rb`, mirroring NIST/CIE). Run `rake spec:update_index` to refresh from relaton-data-plateau.
- RSpec with `expect` syntax (no monkey-patching)
- VCR cassettes record HTTP interactions (in `spec/fixtures/vcr_cassettes/`)
- `equivalent-xml` for XML comparison assertions
- `jing` matcher for RNG schema validation
- SimpleCov for code coverage

## Key Conventions

- Document identifiers are pubid-canonical: `PLATEAU Handbook #XX 第Y.Z版` (Japanese edition) or `PLATEAU Technical Report #XX` (no edition); sub-numbers use a hyphen (`#XX-N`). See "Pubid-backed index" above.
- The gem supports multi-format serialization: XML, YAML, BibXML (RFC XML)
- RuboCop follows Ribose OSS style guide; target Ruby version is 3.0
- The `ext` element in XML/YAML carries PLATEAU-specific metadata (doctype, flavor, editorialgroup, etc.)
