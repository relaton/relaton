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

1. **Bibliography** (`lib/relaton/bsi/bibliography.rb`) — `get(code, year, opts)` / `search` entry points. Reference handling is **entirely `Pubid::Bsi`** (from the unified `pubid` gem) with **no hand-rolled identifier regex**: `parse` wraps `Pubid::Bsi::Identifier.parse` (nil on failure), `publication_year` reads `pubid.base_document.year`, and `same_reference?(query, hit, skip_rest:, drop_amd:)` decides whether a query and a candidate hit denote the same document. `same_reference?` uses only pubid's typed API — `#base_document` (peels supplements + Expert-commentary / Flex-version wrappers), `#matches?(other, ignore: %i[date month])` for the base-document comparison (`:month` is excluded alongside `:date` because Flex stores the month separately, so `exclude(:date)` alone leaves them unequal), and the uniform `Amendment`/`Corrigendum` `#supplement_type`/`#supplement_number`/`#supplement_year` interface (amendment year optional when the query omits it). A canonical `rest_marker` (`:expert_commentary` / `:"flex_<edition>"`) makes an `ExComm` query match an `Expert Commentary` hit. `search` still lightly normalizes the **Algolia query text** (drops `BSI `, abbreviates the Expert-commentary suffix) — search-engine tuning, not identifier parsing. This depends on the `pubid` `feat/bsi-parse-gaps` work (see `HANDOFFS/metanorma__pubid.md`): the three parse/exclude gaps **plus** the Phase-2 API (`#base_document`, `exclude(:amendment|:supplement|:edition)`, uniform supplement accessors, `#matches?`).
2. **HitCollection** (`lib/relaton/bsi/hit_collection.rb`, extends `Relaton::Core::HitCollection`) — queries the Algolia index (`shopify_products`) and filters hits by parsing each hit code and calling `Bibliography.same_reference?` against the parsed query, in three passes: exact → `skip_rest` (ignore the ExComm/Flex-version suffix) → `drop_amd` (compare base documents only, and rewrite the hit id to `hit.base_document.to_s`). Algolia keys are public/client-side.
3. **Hit** (`lib/relaton/bsi/hit.rb`, extends `Relaton::Core::Hit`) — `item` lazy-loads the full document via the scraper; `pubid` memoizes the hit code parsed with `Pubid::Bsi` (like `Relaton::Iso::Hit#pubid`) so the three filter passes don't re-parse it.
4. **Scraper** (`lib/relaton/bsi/scraper.rb`) — GraphQL client; runs schema-based queries against the Shopify storefront GraphQL endpoint to build a full record (titles split on em-dash into intro/main/part, dates, contributors, ICS, source URI).
5. **ItemData / Model::Item** (`item_data.rb`, `model/`) — `Relaton::Bsi::ItemData` extends `Relaton::Iso::ItemData`; `Ext` adds doctype, ICS, and a structured identifier. **Docidentifier** (`model/docidentifier.rb`) keeps the parsed `Pubid::Bsi::Identifier` as the **single stored value** of `content` (via the flavor-agnostic `Iso::Type::Pubid` lutaml type, which preserves the instance in and stringifies it out) — one source of truth: `#pubid` returns the instance, `#content` renders it to a string, and the three mutators re-store an `exclude`-copy of the pubid: `#remove_date!` → `pubid.exclude(:date, :month)`, `#remove_part!` → `pubid.exclude(:part, :subpart)`, `#to_all_parts!` → `pubid.exclude(:part, :subpart, :date, :month)` plus setting the inherited `all_parts` flag. Note BSI's pubid renderer does **not** emit an `(all parts)` marker (unlike ISO), so `to_all_parts!` degrades to a rendered part+date strip while the flag is set structurally (for matching/serialization). All three no-op when `#pubid` is nil. Non-BSI identifiers (e.g. ISBN) and anything pubid can't parse are stored verbatim as plain strings.
6. **Processor** (`lib/relaton/bsi/processor.rb`) — registry integration; lazy-`require_relative`s `../bsi` in its methods.

## External dependencies

`algolia ~> 2.3.0`, `graphql ~> 2.3`, `graphql-client ~> 0.23`, `faraday-net_http_persistent ~> 2.0`, `relaton-core`, `relaton-iso`.

## Testing

RSpec with WebMock + VCR (cassettes in `spec/vcr_cassettes/`, record `:once`, 7-day re-record). Network is blocked via WebMock. No index fixture — BSI has no curated index; `spec/fixtures/` holds XML/YAML round-trip data.
