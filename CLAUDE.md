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

The codebase has two parallel implementations during a migration:

### LutaML Models (v2.0.0, in `lib/relaton/plateau/`)
The new architecture uses LutaML::Model::Serializable for data modeling with automatic XML/YAML/Hash serialization:
- **Item** (`item.rb`) — base Plateau item extending `Bib::Item`, adds `ext` (extension data)
- **Bibitem** (`bibitem.rb`) — bibliographic item variant (includes `Bib::BibitemShared`)
- **Bibdata** (`bibdata.rb`) — bibliographic data variant (includes `Bib::BibdataShared`)
- **Ext** (`ext.rb`) — extension element: doctype, subdoctype, flavor, editorialgroup, stagename, etc.
- **Doctype** (`doctype.rb`) — extends `Bib::Doctype`, valid values: `handbook`, `technical-report`, `annex`

### Legacy Models (v1.x, in `lib/relaton/plateau_legacy/`)
The RelatonBib-based implementation handles data fetching and the Relaton processor interface:
- **Bibliography** — index-based document retrieval via `Bibliography.get(code)`
- **Fetcher** — scrapes MLIT JSON APIs for handbooks and technical reports
- **Parser/HandbookParser/TechnicalReportParser** — parse JSON into BibItem objects
- **Processor** — standard Relaton processor plugin (`get`, `from_xml`, `hash_to_bib`, `fetch_data`)
- **BibItem** — extends `RelatonBib::BibliographicItem` with cover, stagename, filesize

### Data Sources
- Handbooks: `https://www.mlit.go.jp/plateau/_next/data/1.3.0/libraries/handbooks.json`
- Technical Reports: `https://www.mlit.go.jp/plateau/_next/data/1.3.0/libraries/technical-reports.json`
- Pre-fetched index: `https://raw.githubusercontent.com/relaton/relaton-data-plateau/main/`

### Schema Validation
RNG grammar files in `grammars/` define the XML schema. Tests validate fixtures against `relaton-plateau-compile.rng` using the `ruby-jing` gem.

## Testing

- RSpec with `expect` syntax (no monkey-patching)
- VCR cassettes record HTTP interactions (in `spec/fixtures/vcr_cassettes/`)
- `equivalent-xml` for XML comparison assertions
- `jing` matcher for RNG schema validation
- SimpleCov for code coverage

## Key Conventions

- Document identifiers follow pattern: `PLATEAU Handbook #XX Y.Z` or `PLATEAU Technical Report #XX Y.Z`
- The gem supports multi-format serialization: XML, YAML, BibXML, AsciiBib
- RuboCop follows Ribose OSS style guide; target Ruby version is 3.0
- The `ext` element in XML/YAML carries PLATEAU-specific metadata (doctype, flavor, editorialgroup, etc.)
