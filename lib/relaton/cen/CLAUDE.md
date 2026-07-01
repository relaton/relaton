# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-cen retrieves European Committee for Standardization (CEN/CENELEC) bibliographic data using the Relaton model. It has no API or curated index — it **scrapes** the CEN/CENELEC public portal (`standards.cencenelec.eu`) with Mechanize, simulating the search form and parsing HTML tables for title, status, ICS codes, publication dates, and committee info. Uses `Relaton::Bib::ItemData` directly (no relaton-iso dependency).

## Development

```bash
bundle exec rake        # default task → rspec
bundle exec rspec spec/relaton/cen/bibliography_spec.rb   # single file
```

(No gem-local rubocop config; the monorepo root config applies.)

## Architecture

Namespace: `Relaton::Cen`. Retrieval flow:

1. **Bibliography** (`lib/relaton/cen/bibliography.rb`) — `get(code, year, opts)` entry point; `code_to_parts` regex-decomposes a reference (e.g. `EN 123:2020`) into code/part/year/amendment/corrigendum.
2. **HitCollection** (`lib/relaton/cen/hit_collection.rb`, extends `Relaton::Core::HitCollection`) — the web flow: GET the portal, follow the redirect, submit the search form (`STAND_REF`) via Mechanize, parse the result table.
3. **Hit** (`lib/relaton/cen/hit.rb`, extends `Relaton::Core::Hit`) — `item` lazy-loads the detail page via the scraper.
4. **Scraper** (`lib/relaton/cen/scraper.rb`) — Mechanize/XPath HTML parser. Maps CEN date abbreviations (DOR→adapted, DAV→issued, DOA→announced, DOP→published, DOW→obsoleted) and relation headers (supersedes→obsoletes, normative reference→cites); a small `COMMITTEES` map resolves codes like TC 459→ECISS.
5. **ItemData / Model::Item** (`item_data.rb`, `model/`) — `Relaton::Cen::ItemData` extends `Relaton::Bib::ItemData`; `Ext` adds a `StructuredIdentifier` (docnumber/partnumber, agency "CEN").
6. **Processor** (`lib/relaton/cen/processor.rb`) — registry integration. Note: cen's `processor.rb` does `require_relative "../cen"` at file load (eager for this flavor), so its methods don't lazy-require individually.

## External dependencies

`mechanize ~> 2.10`, `isoics ~> 0.1` (ICS descriptions), `relaton-core`, `relaton-bib`.

## Testing

RSpec with WebMock + VCR (cassettes in `spec/vcr_cassettes/`, record `:once`, 7-day re-record). Network is blocked via WebMock. No index fixture — CEN is scraped, not indexed; `spec/fixtures/` holds XML/YAML round-trip data. The scraper is inherently brittle to portal HTML changes.
