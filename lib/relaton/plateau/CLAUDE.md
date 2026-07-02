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
- Pre-fetched index: `https://raw.githubusercontent.com/relaton/relaton-data-plateau/data-v2/`

### Schema Validation
RNG grammar files in `grammars/` define the XML schema. Tests validate fixtures against `relaton-plateau-compile.rng` using the `ruby-jing` gem.

## Testing

- **Index fixture:** `spec/fixtures/index-v1.zip` is pre-loaded into `Relaton::Index` pool in `before(:suite)` (configured in `spec/support/webmock.rb`). Run `rake spec:update_index` to refresh from relaton-data-plateau.
- RSpec with `expect` syntax (no monkey-patching)
- VCR cassettes record HTTP interactions (in `spec/fixtures/vcr_cassettes/`)
- `equivalent-xml` for XML comparison assertions
- `jing` matcher for RNG schema validation
- SimpleCov for code coverage

## Key Conventions

- Document identifiers follow pattern: `PLATEAU Handbook #XX Y.Z` or `PLATEAU Technical Report #XX Y.Z`
- The gem supports multi-format serialization: XML, YAML, BibXML (RFC XML)
- RuboCop follows Ribose OSS style guide; target Ruby version is 3.0
- The `ext` element in XML/YAML carries PLATEAU-specific metadata (doctype, flavor, editorialgroup, etc.)
