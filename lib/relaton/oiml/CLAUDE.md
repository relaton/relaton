# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-oiml retrieves International Organization of Legal Metrology (OIML) publications using the Relaton model. It is **index-backed** (no scraping): it searches a pre-built index via `Relaton::Index` and fetches per-document YAML from the `relaton/relaton-data-oiml` GitHub repo. OIML reference parsing uses `Pubid::Oiml::Identifier`.

## Development

```bash
bundle exec rake                 # default task → rspec
bundle exec rspec spec/relaton/oiml/bibliography_spec.rb   # single file
bundle exec rake spec:update_index   # refresh the OIML index fixture from relaton-data-oiml
```

(No gem-local rubocop config; the monorepo root config applies.)

## Architecture

Namespace: `Relaton::Oiml`. Retrieval flow:

1. **Bibliography** (`lib/relaton/oiml/bibliography.rb`) — `get(code, year)` / `search`; parses the reference with `Pubid::Oiml.parse`, looks it up in the index, and fetches the matching YAML. `get` suppresses the edition year for an **undated** citation (mirroring ISO): when the reference carries no year (and `opts[:keep_year]` is not set) it returns `item.to_most_recent_reference`, so `OIML B 18` renders undated, while a dated citation (`OIML B 18:2022`, or an explicit `year`) still pins that edition. This relies on `Oiml::Docidentifier#remove_date!` refreshing `content` from the dateless pubid — mutating the wrapped `@pubid` alone leaves the rendered `content` dated (issue #72).
2. **Index** — `Relaton::Index.find_or_create(:oiml, url: ..., pubid_class: Pubid::Oiml::Identifier)`. `INDEXFILE` is defined in `lib/relaton/oiml.rb`. `Bibliography#best_row` matches a **Bulletin** exactly (`index.search(query, exact: true)`), and every other type by `pubid_match?`: the year-and-language-stripped "stem" is equal, the language is equal, and the year is equal when the reference or the `year` argument names one; the latest edition wins. A Bulletin needs the exact match because its year is part of its locator: the issue and the sequence render after the year, so the stem reduced every article of one year to `OIML Bulletin`, and a lookup returned an arbitrary one of them.

**OIML does not use pubid's subset match `===` yet**, unlike the other flavors that pubid#408 unblocked. Measured over the full `relaton-data-oiml` index (5,646 rows), `===` disagrees with `pubid_match?` outside the Bulletins on 192 pairs, and each one is a regression: `language` is not `subset_strict`, so a language-less Amendment, Annex or Errata reference reaches its translations (156 pairs); `subpart` is not strict, so `OIML R 137-1 (F)` reaches `OIML R 137-1-2:2012 (F)` (6); and the `year_on_base` render flag is compared, so `OIML R 102 Annex B-C` misses `OIML R 102:1995 Annex B-C` (30). A plain Recommendation escapes the first one only because its render hint `parsed_format` differs, which is luck. The hand-off `metanorma__pubid__oiml-subset-match-strict-language` asks pubid for the fix. `spec/oiml/relaton/oiml/bibliography_spec.rb` pins all of these with an in-memory index ("where the subset match would disagree"), so a later switch must pass them.
3. **Item / ItemData / Ext** (`item.rb`, `item_data.rb`, `ext.rb`) — `Item` extends `Bib::Item`; `Ext` carries OIML-specific fields (scope, quantity, measuring_instrument, focus_area, sustainability_framework, doi). `Item.from_yaml` deserializes the fetched document.
4. **Processor** (`lib/relaton/oiml/processor.rb`) — registry integration; `@prefix = "OIML"`, `@defaultprefix = %r{^OIML\s}`. Lazy-`require_relative`s `../oiml` in its methods, including `remove_index_file`.

There are no scrapers — everything comes from the curated index + GitHub YAML.

## External dependencies

`pubid ~> 2.0.0.pre.alpha.3`, `base64`, `relaton-core`, `relaton-bib`, `relaton-index`.

## Testing

RSpec with WebMock + VCR. The offline index fixture `spec/fixtures/index-v2.zip` is pre-loaded into the `Relaton::Index` pool in `before(:suite)` (configured in `spec/support/webmock.rb`); per-document data requests are stubbed by WebMock and served from `spec/fixtures/data/*.yaml`. Run `rake spec:update_index` to refresh the fixture.
