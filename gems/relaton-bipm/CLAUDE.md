# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-bipm is a Ruby gem that retrieves BIPM (Bureau International des Poids et Mesures) standards metadata for bibliographic use. It's part of the larger Relaton family of gems that handle bibliographic data for standards organizations.

## Common Commands

- **Install dependencies:** `bundle install`
- **Run all tests:** `bundle exec rake spec`
- **Run a single test file:** `bundle exec rspec spec/relaton/bipm/bibliography_spec.rb`
- **Run a single test by line:** `bundle exec rspec spec/relaton/bipm/bibliography_spec.rb:42`
- **Interactive console:** `bin/console`

## Architecture

### Namespace & Module Structure

All code lives under `Relaton::Bipm` (in `lib/relaton/bipm/`). The gem name is `relaton-bipm`, the require path is `relaton/bipm`.

### Key Components

- **`Bibliography`** (`bibliography.rb`) - Main entry point for fetching standards. Searches a relaton-data-bipm GitHub repository index to find and retrieve YAML bibliographic records.
- **`Id`** (`id_parser.rb`) - Parses BIPM reference strings into structured hashes using regex matching. Handles multiple reference formats: outcomes (resolutions, recommendations, decisions), SI Brochure, Metrologia journal articles, and JCGM documents. The `TYPES` hash maps full type names (English/French) to abbreviations (RES, REC, DECN, DECL).
- **`Processor`** (`processor.rb`) - Relaton framework integration point (extends `Relaton::Core::Processor`). Registers prefix `BIPM` and default prefix pattern matching BIPM, CCTF, CCDS, CGPM, CIPM, JCRB, JCGM.
- **`DataFetcher`** (`data_fetcher.rb`) - Bulk fetches from three data sources: `bipm-data-outcomes`, `bipm-si-brochure`, `rawdata-bipm-metrologia`. Delegates to specialized parsers.
- **`Item`** / **`ItemData`** (`model/item.rb`, `item_data.rb`) - The bibliographic item model, extending `Relaton::Bib::Item`. Supports XML, YAML, and JSON serialization.
- **`model/`** directory - Lutaml model classes (Bibdata, Bibitem, Ext, etc.) for XML/YAML serialization.

### Data Sources

The gem fetches from three external datasets:

1. **bipm-data-outcomes** - CGPM/CIPM/committee resolutions, recommendations, decisions
2. **bipm-si-brochure** - SI Brochure documents
3. **rawdata-bipm-metrologia** - Metrologia journal articles (parsed from CrossRef-style data)

### Testing

- **Index fixture:** `spec/fixtures/index-v1.zip` is pre-loaded into `Relaton::Index` pool in `before(:suite)` (configured in `spec/support/webmock.rb`). Run `rake spec:update_index` to refresh from relaton-data-bipm.
Tests use RSpec with VCR cassettes (`spec/vcr_cassettes/`) to record/replay HTTP interactions. WebMock is used to prevent real HTTP requests during tests. Test fixtures are in `spec/fixtures/`.

### Dependencies

Key runtime dependencies: `relaton-bib` (core bibliographic model), `relaton-index` (index management), `relaton-core` (framework base), `parslet` (PEG parser), `mechanize` (HTTP), `faraday`, `rubyzip`.
