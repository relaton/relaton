# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-jis is a Ruby gem that retrieves Japanese Industrial Standards (JIS) metadata from webdesk.jsa.or.jp and models them as Relaton bibliographic items with XML/YAML serialization and RelaxNG schema validation.

## Commands

- `bundle exec rake spec` — run all tests
- `bundle exec rspec spec/relaton/jis/item_spec.rb` — run a single test file
- `bundle exec rspec spec/relaton/jis/item_spec.rb:15` — run a single test by line number
- `bundle exec rake rubocop` — lint
- `bundle exec rake` — default task (runs specs)

## Architecture

The gem is currently on the `lutaml-integration` branch, a major refactoring from the old `RelatonJis::` namespace to `Relaton::Jis::` using lutaml-model for data modeling.

### Class Hierarchy

All classes live under `lib/relaton/jis/`:

- **`Item`** (extends `Iso::Item`) — core bibliographic item; defines the `Ext` attribute for JIS extensions; uses model `Bib::ItemData`
- **`Bibitem`** (extends `Item`, includes `Bib::BibitemShared`) — XML bibitem serialization
- **`Bibdata`** (extends `Item`, includes `Bib::BibdataShared`) — XML bibdata wrapper
- **`Ext`** (extends `Iso::Ext`) — JIS-specific extension data (schema_version, doctype)
- **`Doctype`** (extends `Bib::Doctype`) — allowed types: `japanese-industrial-standard`, `technical-report`, `technical-specification`, `amendment`
- **`Scraper`** — scrapes individual JIS document pages from webdesk.jsa.or.jp; returns `Bib::ItemData`; editorial group is modeled as a contributor with `Bib::Subdivision` (not `EditorialGroup`)
- **`DataFetcher`** (extends `Core::DataFetcher`) — bulk-fetches all JIS documents via threaded scraping; implements `to_yaml`/`to_xml`/`to_bibxml` for serialization dispatch; loaded on-demand via `require "relaton/jis/data_fetcher"`
- **`Processor`** (extends `Core::Processor`) — Relaton processor registration; provides `get`, `fetch_data`, `from_xml`, `from_yaml`, `grammar_hash`; prefix `JIS`, defaultprefix `^(JIS|TR)\s`
- **`Util`** (includes `Relaton::Bib::Util`) — logging with PROGNAME "relaton-jis"

### Key Dependencies

- **relaton-iso / relaton-bib** — parent bibliographic item models this gem extends
- **lutaml-model** — DSL for `attribute` definitions and serialization
- **mechanize** — web scraping from JSA website

### Serialization & Validation

- YAML and XML round-trip serialization via lutaml-model
- RelaxNG grammars in `grammars/` validate XML output; `relaton-jis.rng` defines JIS-specific elements (DocumentType, structuredidentifier, stagename)
- Tests validate XML against these grammars using ruby-jing

### Test Patterns

- **Round-trip tests**: YAML → Object → YAML and XML → Object → XML (fixtures in `spec/fixtures/`)
- **Schema validation**: Jing validates generated XML against RelaxNG grammars
- **HTTP mocking**: VCR cassettes (`spec/vcr_cassettes/`) record external HTTP interactions; WebMock disables real network calls in tests

## Code Conventions

- All files use `# frozen_string_literal: true`
- Linting follows [Ribose OSS style](https://github.com/riboseinc/oss-guides); target Ruby 3.1
- Ruby >= 3.1.0 required

## Testing

- **Index fixture:** `spec/fixtures/index-v2.zip` (the pubid-based `index-v2`) is deserialized via `Pubid::Jis::Identifier` and pre-loaded into the `Relaton::Index` pool in `before(:suite)` (configured in `spec/support/webmock.rb`). Run `rake spec:update_index` to refresh from relaton-data-jis.
- **Lookup path:** `Bibliography.get`/`search` parse the reference with `pubid`, then `HitCollection` matches against `index-v2` (`Hit#matches?` compares type/series/number/part; year is filtered separately). The `DataFetcher` still generates `index-v1` too, but the runtime no longer reads it.
- **pubid dependency:** the gemspec requires `pubid ~> 2.0.0.pre.alpha.3`, the published release carrying the working lutaml-model `from_hash` (the earlier `2.0.0.pre.alpha.2` was broken). Override to a local checkout with `bundle config set local.pubid /path/to/pubid`.
