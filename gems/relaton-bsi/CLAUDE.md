# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-bsi retrieves British Standards Institution (BSI) bibliographic data using the Relaton model. Unlike index-backed flavors, it searches the BSI Shopify storefront: an **Algolia** product index finds candidate standards, then a **GraphQL** query against the Shopify storefront API fetches full metadata (titles, dates, ISBNs, committee info). Depends on relaton-iso for its ISO-based item/extension models.

## Development

```bash
bundle exec rake        # default task → rspec
bundle exec rspec spec/relaton/bsi/bibliography_spec.rb   # single file
```

(No gem-local rubocop config; the monorepo root config applies.)

## Architecture

Namespace: `Relaton::Bsi`. Retrieval flow:

1. **Bibliography** (`lib/relaton/bsi/bibliography.rb`) — `get(code, year, opts)` / `search` entry points; normalizes a BSI reference and delegates to the hit search.
2. **HitCollection** (`lib/relaton/bsi/hit_collection.rb`, extends `Relaton::Core::HitCollection`) — queries the Algolia index (`shopify_products`) and filters hits to the requested code. Algolia keys are public/client-side.
3. **Hit** (`lib/relaton/bsi/hit.rb`, extends `Relaton::Core::Hit`) — `item` lazy-loads the full document via the scraper.
4. **Scraper** (`lib/relaton/bsi/scraper.rb`) — GraphQL client; runs schema-based queries against the Shopify storefront GraphQL endpoint to build a full record (titles split on em-dash into intro/main/part, dates, contributors, ICS, source URI).
5. **ItemData / Model::Item** (`item_data.rb`, `model/`) — `Relaton::Bsi::ItemData` extends `Relaton::Iso::ItemData`; `Ext` adds doctype, ICS, and a structured identifier.
6. **Processor** (`lib/relaton/bsi/processor.rb`) — registry integration; lazy-`require_relative`s `../bsi` in its methods.

## External dependencies

`algolia ~> 2.3.0`, `graphql ~> 2.3`, `graphql-client ~> 0.23`, `faraday-net_http_persistent ~> 2.0`, `relaton-core`, `relaton-iso`.

## Testing

RSpec with WebMock + VCR (cassettes in `spec/vcr_cassettes/`, record `:once`, 7-day re-record). Network is blocked via WebMock. No index fixture — BSI has no curated index; `spec/fixtures/` holds XML/YAML round-trip data.
