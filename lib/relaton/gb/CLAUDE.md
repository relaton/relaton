# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-gb retrieves Chinese National Standards (Guobiao — `GB`, `GB/T`, `GB/Z`, plus social-org and sector standards) using the Relaton model. It scrapes several Chinese government portals (`openstd.samr.gov.cn`, `ttbz.org.cn`, `std.gov.cn`) with Mechanize. Depends on relaton-iso for ISO-based item/extension models, and on Chinese-specific classifiers (`cnccs`, `gb-agencies`).

## Development

```bash
bundle exec rake        # default task → rspec
bundle exec rspec spec/relaton/gb/bibliography_spec.rb   # single file
```

(RuboCop is configured via the shared `.hound.yml`; the monorepo root config applies otherwise.)

## Architecture

Namespace: `Relaton::Gb`. Note: GB places its model classes at the top of `lib/relaton/gb/` (`item.rb`, `bibitem.rb`, `bibdata.rb`, `ext.rb`, …) rather than under a `model/` subdir.

Retrieval flow:

1. **Bibliography** (`lib/relaton/gb/bibliography.rb`) — `get`/`search` dispatch by prefix: `GB*` → `GbScraper` (openstd.samr.gov.cn), `T/` → `TScraper` (ttbz.org.cn), others → `SecScraper` (std.gov.cn).
2. **Scrapers** (`scraper.rb` + `gb_scraper.rb` / `t_scraper.rb` / `sec_scraper.rb`) — scrape the relevant portal for hits, then scrape the detail page into an `ItemData`.
3. **HitCollection / Hit** (`hit_collection.rb`, `hit.rb`, extend the `Relaton::Core` bases) — `Hit#item` lazy-loads the document; a hit holds `pid`, `docref`, `release_date`, `status`.
4. **Item / ItemData / Ext** (`item.rb`, `item_data.rb`, `ext.rb`) — `Item` extends `Bib::Item`; `Ext` carries GB-specific fields (`gbtype`, `ccs`, `stagename`, `plannumber`). Supporting models: `gb_type.rb`, `ccs.rb` (Chinese classification), `stage_name.rb`, `committee.rb`, `structured_identifier.rb`.
5. **Processor** (`lib/relaton/gb/processor.rb`) — registry integration; `@prefix = "CN"`, `@defaultprefix = %r{^(GB|GB/T|GB/Z) }`. Lazy-`require_relative`s `../gb` in its methods.

## External dependencies

`cnccs ~> 0.1.1`, `gb-agencies ~> 0.0.1`, `mechanize ~> 2.10`, `csv ~> 3.0`, `relaton-core`, `relaton-iso`.

## Testing

RSpec with WebMock + VCR (cassettes in `spec/vcr_cassettes/`). Network is blocked via WebMock. SimpleCov and equivalent-xml are loaded via `spec/support/`. No index fixture — GB is scraped, not indexed; `spec/fixtures/` holds XML/YAML round-trip data.
