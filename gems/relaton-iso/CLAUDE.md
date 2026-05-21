# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development

- `bin/setup` — install dependencies
- `rake spec` — run tests
- `rspec spec/relaton/iso/bibliography_spec.rb` — run a single test file
- `rspec spec/relaton/iso/bibliography_spec.rb -e "some description"` — run a specific example
- `rake spec:update_index` — download latest ISO index fixture (`spec/fixtures/index-v1.zip`) from relaton-data-iso
- `bin/console` — interactive prompt with the gem loaded
- `rubocop` — lint (Ribose OSS style guide, Ruby 3.2 target)

## Architecture

relaton-iso retrieves ISO standard bibliographic data. The core retrieval flow:

1. **Bibliography** (`lib/relaton/iso/bibliography.rb`) — entry point via `search(pubid)` and `get(ref, year, opts)`. Handles year filtering, part matching, and type/stage validation.
2. **HitCollection** (`lib/relaton/iso/hit_collection.rb`) — searches a pre-built YAML index (`index-v1.zip` from relaton-data-iso) using `Relaton::Index`. Matches on `id_keys`: publisher, number, copublisher, part, year, edition, type, stage, iteration. Returns sorted Hit array.
3. **Hit** (`lib/relaton/iso/hit.rb`) — wraps an index result. The `item` attribute lazy-loads the full document from GitHub raw content (relaton-data-iso repo). `sort_weight` prioritizes published over withdrawn/deleted.
4. **ItemData** / **Model::Item** — ISO-specific bibliographic item extending `Relaton::Bib::ItemData`.
5. **Scraper** (`lib/relaton/iso/scraper.rb`) — parses individual ISO website pages. Used only by `Bibliography.get` as a fallback when an item is missing from the curated index; no longer drives bulk ingest.
6. **DataFetcher** (`lib/relaton/iso/data_fetcher.rb`) — streams the ISO Open Data programme JSONL feeds (`iso_deliverables_metadata.jsonl` for documents, `iso_technical_committees.jsonl` for committee titles) and writes one YAML per primary docid into `@output`. Short-circuits on upstream `Last-Modified`; falls back to a full pass when `data/` or `index-v1.yaml` is missing. Two source modes:
   - `iso-open-data` (default) — incremental, skip when upstream is unchanged.
   - `iso-open-data-all` — wipe `@output` and re-emit every record.
7. **DataParser** (`lib/relaton/iso/data_parser.rb`) — converts one Open Data record (`Hash`) into a `Relaton::Iso::ItemData`. Takes a `ref_index` (id → reference) for resolving `replaces`/`replacedBy` and a `tc_index` (reference → `{ "en"/"fr" => title }`) for resolving committee labels.

Key dependency: `pubid-iso` gem handles ISO publication identifier parsing and comparison.

## Testing

- **Framework:** RSpec with VCR cassettes and WebMock
- **Network access:** fully blocked via `WebMock.disable_net_connect!`
- **Index fixture:** `spec/fixtures/index-v1.zip` is pre-loaded into `Relaton::Index` pool in `before(:suite)` (configured in `spec/support/webmock.rb`). Run `rake spec:update_index` to refresh from relaton-data-iso.
- **VCR:** cassettes in `spec/vcr_cassettes/`, record mode `:once`, re-record interval 7 days. Index download requests are ignored by VCR (handled by fixture instead).
