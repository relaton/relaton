# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this gem does

Retrieves bibliographic items from the OpenLibrary API by ISBN (10 or 13 digit) and returns `Relaton::Bib::ItemData` objects. Part of the Relaton family of gems.

## Commands

```sh
bundle exec rspec                          # run all tests
bundle exec rspec spec/relaton/isbn/parser_spec.rb  # run single spec file
bundle exec rubocop                        # lint
bin/console                                # IRB with gem loaded
```

## Architecture

Request flow: `OpenLibrary.get(code)` → `Isbn.new(code).parse` (validates/normalizes ISBN) → `OpenLibrary.request_api(isbn)` (HTTP to openlibrary.org) → `Parser.parse(json)` (builds `ItemData`)

Key modules under `Relaton::Isbn`:
- **OpenLibrary** — API client, main entry point via `.get`
- **Isbn** — ISBN-10/13 validation and conversion (always normalizes to ISBN-13)
- **Parser** — Transforms OpenLibrary JSON into `Relaton::Bib::ItemData` with titles, contributors, dates, etc.
- **Processor** — Integration hook for relaton-core framework (`from_xml`, `from_yaml`, `get`)
- **Util** — Logging via `Relaton::Bib::Util`

## Data model (relaton-bib 2.0)

Uses `Relaton::Bib::` namespace (not the old `RelatonBib::`). Key classes: `ItemData`, `Title`, `Docidentifier` (uses `.content` not `.id`), `Uri`, `Contributor`, `Person`, `Organization`, `Date` (uses `at:` not `on:`), `Place`.

`Parser#parse` returns `Bib::ItemData` (not `Bibitem`) — `ItemData` is the plain data class; `Bibitem`/`Item` are lutaml-model serializers that wrap it.

## Testing

- **VCR** records HTTP interactions in `spec/vcr_cassettes/` (re-records every 7 days)
- **WebMock** disables real HTTP by default
- **SimpleCov** tracks coverage
- Fixtures in `spec/fixtures/`

## Style

- RuboCop with Ribose OSS style guide, target Ruby 3.1
- `rubocop-rails` is required but Rails cops are disabled (not a Rails app)
