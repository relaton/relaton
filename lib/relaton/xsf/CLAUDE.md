# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is relaton-xsf?

A Ruby gem for bibliographic retrieval of XMPP XEP (XMPP Extension Protocol) specifications. Part of the Relaton family of gems. Fetches data from https://xmpp.org/extensions/refs/ and the relaton-data-xsf GitHub repository.

## Commands

- `bundle exec rspec` — run all tests
- `bundle exec rspec spec/relaton/xsf/processor_spec.rb` — run a single spec file
- `bundle exec rubocop` — lint
- `bundle exec rubocop -a` — lint with auto-fix
- `bin/console` — interactive console with gem loaded

## Architecture

Namespace: `Relaton::Xsf` (under `lib/relaton/xsf/`). Branch `lutaml-integration` uses the new nested namespace (not the old `RelatonXsf`).

Key classes and their base classes from relaton-core:

| Class | Base | Role |
|---|---|---|
| `Processor` | `Relaton::Core::Processor` | Plugin entry point for relaton registry |
| `Bibliography` | Module (extends self) | Search & get interface (`search`, `get`) |
| `HitCollection` | `Relaton::Core::HitCollection` | Collection of search results |
| `Hit` | `Relaton::Core::Hit` | Single result; lazy-loads YAML from GitHub |
| `DataFetcher` | `Relaton::Core::DataFetcher` | Crawls xmpp.org, parses BibXML, saves docs |
| `Item` / `Bibitem` / `Bibdata` | `Relaton::Bib::Item` | Bibliographic item models (lutaml-model based) |

Data flow: `Processor#get` → `Bibliography.get` → `HitCollection.search` → `Hit#item` → fetches YAML → `Relaton::Bib::Item.from_yaml`

DataFetcher flow: Crawls `https://xmpp.org/extensions/refs/`, parses each XML ref via `Relaton::Bib::Converter::BibXml.to_item`, sets `ext.flavor = "xsf"`, saves to disk.

Constants: `INDEXFILE = "index-v1"`, `GHDATA_URL` points to relaton-data-xsf `v2` branch.

## Testing

- **Index fixture:** `spec/fixtures/index-v1.zip` is pre-loaded into `Relaton::Index` pool in `before(:suite)` (configured in `spec/support/webmock.rb`). Run `rake spec:update_index` to refresh from relaton-data-xsf.
- RSpec with VCR cassettes (`spec/vcr_cassettes/`) for HTTP interactions
- WebMock disables all external network connections
- Fixtures in `spec/fixtures/` (item.yaml, bibdata.xml, bibitem.xml)
- Round-trip tests verify YAML→Item→YAML and XML→Item→XML fidelity
- `DataFetcher` is lazily required — specs that test it must `require "relaton/xsf/data_fetcher"` explicitly
- Same for `Processor` — `require "relaton/xsf/processor"`

## Key dependencies

- `relaton-core` — abstract base classes (Processor, HitCollection, Hit, DataFetcher)
- `relaton-bib` — bibliographic models, XML/YAML serialization (lutaml-model based)
- `relaton-index` — index management for quick document lookups
- `mechanize` — HTTP fetching and HTML parsing

## Style

- RuboCop with relaton shared config (inherits from riboseinc/oss-guides)
- Target Ruby version: 3.1
- Logging via `Relaton::Xsf::Util` (extends `Relaton::Bib::Util`, PROGNAME = "relaton-xsf")
