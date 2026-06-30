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

1. **Bibliography** (`lib/relaton/oiml/bibliography.rb`) — `get(code, year)` / `search`; parses the reference with `Pubid::Oiml.parse`, looks it up in the index, and fetches the matching YAML.
2. **Index** — `Relaton::Index.find_or_create(:oiml, url: ..., pubid_class: Pubid::Oiml::Identifier)`; matches by pubid then filters by year/language (`pubid_match?`). `INDEXFILE` is defined in `lib/relaton/oiml.rb`.
3. **Item / ItemData / Ext** (`item.rb`, `item_data.rb`, `ext.rb`) — `Item` extends `Bib::Item`; `Ext` carries OIML-specific fields (scope, quantity, measuring_instrument, focus_area, sustainability_framework, doi). `Item.from_yaml` deserializes the fetched document.
4. **Processor** (`lib/relaton/oiml/processor.rb`) — registry integration; `@prefix = "OIML"`, `@defaultprefix = %r{^OIML\s}`. Lazy-`require_relative`s `../oiml` in its methods, including `remove_index_file`.

There are no scrapers — everything comes from the curated index + GitHub YAML.

## External dependencies

`pubid ~> 2.0.0.pre.alpha.3`, `base64`, `relaton-core`, `relaton-bib`, `relaton-index`.

## Testing

RSpec with WebMock + VCR. The offline index fixture `spec/fixtures/index-v2.zip` is pre-loaded into the `Relaton::Index` pool in `before(:suite)` (configured in `spec/support/webmock.rb`); per-document data requests are stubbed by WebMock and served from `spec/fixtures/data/*.yaml`. Run `rake spec:update_index` to refresh the fixture.
