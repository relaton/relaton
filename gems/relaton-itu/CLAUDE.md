# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-itu is a Ruby gem for retrieving ITU (International Telecommunication Union) standards metadata. Part of the Relaton family of gems maintained by Ribose Inc.

## Commands

```bash
bundle exec rake spec          # Run full test suite
bundle exec rspec spec/relaton/itu/              # Run new-namespace tests only
bundle exec rspec spec/relaton/itu/item_spec.rb  # Run a single spec file
bundle exec rspec spec/relaton/itu/item_spec.rb:15  # Run a specific test by line
bin/console                    # Interactive Ruby console with gem loaded
```

No separate lint command is configured; RuboCop can be run via `bundle exec rubocop`.

## Architecture

### Namespace Migration (In Progress)

The codebase is migrating from flat `RelatonItu` namespace (`lib/relaton_itu/`) to nested `Relaton::Itu` (`lib/relaton/itu/`). Both namespaces coexist:

- **`lib/relaton/itu/`** — New namespace. Model classes, DataFetcher, DataParserR, Processor, Util, Version are here.
- **`lib/relaton_itu/`** — Old namespace. ItuBibliography, XMLParser, ItuBibliographicItem, HitCollection, and others still live here.

The `Processor` class (`Relaton::Itu::Processor`) bridges both: it lives in the new namespace but calls old-namespace classes (`::RelatonItu::ItuBibliography`, `::RelatonItu::XMLParser`, etc.) for functionality not yet migrated.

### Model Layer (Lutaml::Model)

All model classes use `Lutaml::Model::Serializable` for XML/YAML serialization:

- **`Item`** → extends `Bib::Item` (main bibliographic item)
- **`ItemData`** → extends `Bib::ItemData` (used by DataParserR for parsed documents)
- **`Bibitem`** / **`Bibdata`** → extend `Item`, mix in shared behavior from `Bib`
- **`Ext`** → extends `Bib::Ext` with ITU-specific fields (doctype, structuredidentifier, question, recommendationstatus, ip_notice_received, meeting, meeting_place, meeting_date, intended_type, source)
- **`Doctype`**, **`StructuredIdentifier`**, **`EditorialGroup`**, **`Bureau`**, **`Group`**, **`ApprovalStage`**, **`RecommendationStatus`**, **`Question`**, **`Meeting`**, **`MeetingDate`** — ITU-specific metadata types

### Data Fetching

- **`DataFetcher`** extends `Core::DataFetcher` — orchestrates fetching ITU-R documents from `extranet.itu.int`
- **`DataParserR`** — module that parses ITU-R JSON search API results into `ItemData` instances (sets `flavor: "itu"` on all parsed documents)
- Sources: recommendations (JSON index), questions, reports, handbooks, resolutions (HTML indices)

### Processor

`Relaton::Itu::Processor` extends `Relaton::Core::Processor` and is the entry point for the Relaton plugin system. Provides `get`, `fetch_data`, `from_xml`, `hash_to_bib`, `grammar_hash`, and `remove_index_file`.

## Testing

- **Index fixture:** `spec/fixtures/index-v1.zip` is pre-loaded into `Relaton::Index` pool in `before(:suite)` (configured in `spec/support/webmock.rb`). Run `rake spec:update_index` to refresh from relaton-data-itu-r.
- **Framework:** RSpec with VCR cassettes for HTTP mocking and WebMock
- **Fixtures:** `spec/fixtures/` contains sample YAML/XML documents for round-trip tests
- **VCR cassettes:** `spec/vcr_cassettes/` — 22 cassettes recording real HTTP responses
- **Coverage:** SimpleCov, target near 100%

Round-trip tests (serialize → deserialize → compare) are the primary pattern for model classes.

## Key Dependencies

- `relaton-bib` — base bibliographic model classes (`Bib::Item`, `Bib::Ext`, etc.)
- `relaton-core` — `Core::Processor`, `Core::DataFetcher` base classes
- `lutaml-model` — serialization framework (XML/YAML mapping via `Lutaml::Model::Serializable`)
- `mechanize` — web scraping for data fetching
- `relaton-index` — document indexing

## Ruby Version

Requires Ruby >= 3.1.0.
