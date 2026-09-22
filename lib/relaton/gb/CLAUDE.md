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
5. **Processor** (`lib/relaton/gb/processor.rb`) — registry integration; `@prefix = "CN"`, `@defaultprefix = %r{^(GB|GB/T|GB/Z) }`, `@pubid_flavor = :Gb`. Lazy-`require_relative`s `../gb` in its methods.

## Identifiers (pubid)

GB parses identifiers with `Pubid::Gb::Identifier`. It publishes no index, so it has no `INDEXFILE` and no `pubid_class:` (the BSI/CEN shape, see the root `CLAUDE.md`). The attributes it reads are `publisher`, `mandate`, `number`, `part`, `year` and `all_parts`.

- **Query side raises.** `Bibliography.get` parses the caller's code without a rescue, so a reference that is not a GB identifier raises `Pubid::Errors::ParseError`. The year comes from the argument or from `pubid.year`; `all_parts` sets `part = "1"` on the pubid to find part 1. `search` still routes on the raw string (`GB|GJ|GS` → `GbScraper`, `T/…` → `TScraper`, else `SecScraper`), so the portal for each reference and the cassettes are unchanged.
- **Hit filter.** `search_filter` parses each `hit.docref` (rescued: a docref is data; an unparseable one drops the hit) and keeps the hits that `query.matches?`. It ignores `:year` only when the query has no year. It **never** ignores `:part`: `GB/T 20223` and `GB/T 20223.1` are two documents, and `gb_spec.rb` asserts that `GB/T 20223-2006` does not return `GB/T 20223.1-2006`. This is a deliberate departure from the migration hand-off, which proposed to ignore a part the query omits. It also stops `GB/T 1.1` from matching `GB/T 1.10`, which the old substring compare allowed.
- **`Docidentifier`** (`docidentifier.rb`) follows the CEN/OMG shape: `content=` parses into `@pubid` (rescued, data side), and the mutators replace the pubid with an `exclude` copy and write back through `store_content`. `to_all_parts!` excludes part and year, sets `all_parts`, and pubid renders the ` (all parts)` suffix itself (and parses it back). A nil pubid makes every mutator a no-op.
- **Scrapers** (`scraper.rb`) read the docref through a rescued `docref_pubid`. `get_prefix` keys `yaml/prefixes.yaml` with the first segment of `publisher` (a `Pubid::Components::Publisher`, so read it as `publisher.to_s`; `T/GZAEPI` → `T`). An unknown key gives nil, and `get_gbtype` keeps a nil prefix rather than raising — a portal docref is data. `get_mandate` maps `mandate` `T` → recommended, `Z` → guidelines, nil → mandatory. `get_contributors` passes `publisher.to_s` to `gb_agencies`, which names the same organization for `GB` and `GB/T`. `parse_docref` returns `[id without part and year, part, year]`; the first value is `plannumber`.
- **Pubid traps.** `Pubid::Gb` accepts any upper-case publisher code (`ISO 123` parses), so use `foo` or `GB/T` for a parse-error example. `year` is a reader over `date` (no `year=`); set it with `date = Pubid::Components::Date.new(year:)`. Local (`DB11/T`) forms do not parse. pubid PR #388 (`dcea7380`) renamed `publisher_code` to the `publisher` component, added the year to `to_hash`, and made `GBn` parse; a pubid older than that breaks this flavor. pubid renders an em dash (`T/GZAEPI 001—2018`) as a hyphen; the fixture `tgzaepi_001_2018.xml` still records the em dash, and its spec is pending until pubid decides.
- **Prefix register.** `@pubid_flavor = :Gb` sources `Relaton.prefix_flavor` from `Pubid::Gb.prefixes`, so `GB`, `GB/T`, `JB/T`, `T/` … resolve to `Relaton::Gb`. `CN` is not a pubid prefix, so `prefix_flavor("CN")` is `[]`; no caller in this repo used it, and `Db` routing still reads `@prefix`. `HB` resolves to `[Gb, Nist, Bsi]`, pinned in `spec/relaton/prefix_flavor_spec.rb`.

## External dependencies

`cnccs ~> 0.1.1`, `gb-agencies ~> 0.0.1`, `mechanize ~> 2.10`, `csv ~> 3.0`, `relaton-core`, `relaton-iso`.

## Testing

RSpec with WebMock + VCR (cassettes in `spec/vcr_cassettes/`). Network is blocked via WebMock. SimpleCov and equivalent-xml are loaded via `spec/support/`. No index fixture — GB is scraped, not indexed; `spec/fixtures/` holds XML/YAML round-trip data.
