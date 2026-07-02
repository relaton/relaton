# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-oasis is a Ruby gem for retrieving and serializing OASIS Standards bibliographic metadata. It is part of the Relaton family of gems and implements the IsoBibliographicItem model for OASIS standards. Uses the lutaml-model pattern on the `lutaml-integration` branch.

## Commands

```bash
bundle exec rake spec       # Run all tests (default rake task)
bundle exec rake rubocop    # Run linter
bundle exec rspec           # Run tests directly
bundle exec rspec spec/relaton/oasis/bibitem_spec.rb  # Run a single test file
bin/console                 # Interactive IRB with gem loaded
```

## Architecture

### Class Hierarchy (under `Relaton::Oasis`)

All model classes use the lutaml-model pattern from `relaton-bib`:

- **ItemData** (`lib/relaton/oasis/item_data.rb`) — Data model class extending `Bib::ItemData`
- **Item** (`lib/relaton/oasis/item.rb`) — Base class extending `Bib::Item`, uses `ItemData` model, adds `ext` attribute of type `Ext`
- **Bibitem** (`lib/relaton/oasis/bibitem.rb`) — Extends `Item`, includes `Bib::BibitemShared` for individual bibliography entries
- **Bibdata** (`lib/relaton/oasis/bibdata.rb`) — Extends `Item`, includes `Bib::BibdataShared` for complete bibliography records
- **Ext** (`lib/relaton/oasis/ext.rb`) — Extends `Bib::Ext`, OASIS-specific metadata: `doctype`, `technology_area`, `schema_version`
- **Doctype** (`lib/relaton/oasis/doctype.rb`) — Extends `Bib::Doctype`, valid values: `specification`, `memorandum`, `resolution`, `standard`

### Bibliography (under `Relaton::Oasis`)

- **Bibliography** (`lib/relaton/oasis/bibliography.rb`) — Module with `search`/`get` class methods for fetching OASIS standards from the relaton-data-oasis GitHub repository. Delegates to private methods: `find_index_entry`, `fetch_yaml`, `parse_item`

### Data Fetching (under `Relaton::Oasis`)

These classes scrape https://www.oasis-open.org/standards/ to produce YAML/XML data files. Loaded separately via `require "relaton/oasis/data_fetcher"`.

- **DataFetcher** (`lib/relaton/oasis/data_fetcher.rb`) — Extends `Core::DataFetcher`, orchestrates fetching all OASIS standards
- **DataParser** (`lib/relaton/oasis/data_parser.rb`) — Parses individual OASIS document nodes into `ItemData`
- **DataPartParser** (`lib/relaton/oasis/data_part_parser.rb`) — Parses multi-part OASIS document nodes into `ItemData`
- **DataParserUtils** (`lib/relaton/oasis/data_parser_utils.rb`) — Shared module included by both parsers; provides contributor parsing, docid construction, retry logic, and doctype detection

### Serialization

Supports XML (with RELAX NG schema validation via `grammars/`) and YAML round-trip serialization. Classes use `from_xml`/`to_xml` and `from_yaml`/`to_yaml` class methods inherited from the lutaml-model base.

### Test Conventions

Tests are round-trip based: parse a fixture file, serialize back, and compare output to input. XML tests also validate against the RELAX NG schema (`grammars/relaton-oasis-compile.rng`) using the `ruby-jing` gem. Fixtures live in `spec/fixtures/`. VCR cassettes record HTTP interactions in `spec/vcr_cassettes/`. Private methods are tested via `send(:method_name, ...)`.

## Style

RuboCop config inherits from the Ribose OSS style guide. Target Ruby version: 3.4. Rails cops are required but disabled.

## Testing

- **Index fixture:** `spec/fixtures/index-v1.zip` is pre-loaded into `Relaton::Index` pool in `before(:suite)` (configured in `spec/support/webmock.rb`). Run `rake spec:update_index` to refresh from relaton-data-oasis.
