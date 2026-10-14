# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-evs retrieves Estonian standardisation (EVS, Eesti Standardimis- ja
Akrediteerimiskeskus) bibliographic data using the Relaton model. Like CEN/BSI,
it publishes **no index and has no data repo**: the flavor **scrapes** the EVS
e-shop (`www.evs.ee`) with Mechanize. Reference handling is entirely
`Pubid::Evs` (the `:evs` flavor, registered in pubid's registry). EVS records
are dominated by **adoptions**: `EVS-EN …` adopts a European document,
`EVS-EN ISO …` a European adoption of an international one, `EVS-ISO …` /
`EVS-IEC …` adopt international documents directly. The adoption is expressed
with `adoptedFrom` relations parsed from the page's "Base Documents" group.

## Development

```bash
bundle exec rake spec:evs                       # the EVS suite
cd spec/evs && bundle exec rspec -I . relaton/evs/docidentifier_spec.rb
```

(No gem-local rubocop config; the monorepo root config applies.)

## Architecture

Namespace: `Relaton::Evs`. This is the **BSI/CEN shape**: parse the query with
pubid, select the hit with pubid, back the `Docidentifier` with pubid. No
`INDEXFILE`, no `pubid_class:`, no data repo. **Don't add an index** (unless a
`relaton-data-evs` repo appears — relaton#164 tracks that possibility).

Retrieval flow:

1. **Bibliography** (`lib/relaton/evs/bibliography.rb`) — `get(code, year,
   opts)` / `search` / `parse`. `parse` wraps `Pubid::Evs.parse` and **raises**
   on an unrecognized query (root CLAUDE.md law); only the data side rescues,
   in `Hit#pubid`. `get` keeps an early `nil` for an **empty** reference and
   accepts the flavor's own pubid without mutating it (`Relaton::Db` hands it
   the parse it routed). Transport errors are rescued **by name**
   (`Net::ReadTimeout`, `Net::OpenTimeout` → `Relaton::RequestError`, which
   `Db#net_retry` retries).
2. **HitCollection** (`hit_collection.rb`) — the search is a **direct slug
   probe**, not a form submit: the catalogue URL is the printed reference
   slugified (`EVS-EN 18216:2026` → `/en/evs-en-18216-2026`), so the product
   page exists iff the reference denotes a published document. A miss
   **redirects** to `/page-not-found` (HTTP 302, followed by Mechanize) — that
   redirect target is the "no hit" signal; a hard 4xx/5xx raises
   `Mechanize::ResponseCodeError` and is a miss (`hits` rescues to `[]`).
   The `et`/`et-en` language codes probe the `/et/` locale, which serves the
   Estonian-language product.
   - **The hit's `code` keeps the language code** (only the slug derivation
     strips it): the filter `query === hit.pubid` needs the language ON the
     hit for a language-carrying query to match its own record.
   - A reference **without a year** probes `…-<number>` and misses — the
     catalogue URL always carries the year. "Not found." is honest there; do
     not add a search-endpoint fallback without evidence the shop renders one
     server-side (its search is client-rendered).
   - Slug shapes verified against the live catalogue: plain `EVS 945:2023`,
     `EVS-EN 16798-1:2019`, `EVS-EN ISO 14001:2026`, the ETSI face
     `EVS-EN 301 406-1 V3.2.1:2026`, `EVS-EN IEC 61000-4-30:2026`.
3. **Hit** (`hit.rb`) — `item` lazy-loads the detail page via the scraper;
   `pubid` memoizes the hit code parsed with pubid and is **nil** when the
   grammar cannot read it.
4. **Scraper** (`scraper.rb`) — Mechanize/XPath over the product page:
   `h1` → docidentifier, `h2.product-title` → title (`Bib::Title.from_string`
   splits " - " into intro/main — it returns an Array, don't re-wrap), the
   "Valid from dd.mm.yyyy" badge → `published` date, "Base Documents" →
   `adoptedFrom` relations (a double adoption lists both bases in ONE text
   node, `ISO 14001:2026; EN ISO 14001:2026` — split on the semicolon), the
   scope tab (`div#tab-1`) → abstract, ICS group links → `Ext.ics` via
   `Isoics`. Contributor/copyright: the EVS organization (publisher); place
   Tallinn.
5. **ItemData / models** (`item_data.rb`, `model/`) — `Relaton::Evs::ItemData`
   extends `Relaton::Bib::ItemData`; `Ext` adds a `StructuredIdentifier`
   (docnumber/partnumber from the pubid **root**, agency "EVS"). There is no
   `relaton-model-evs` gem, so `Ext` does not override `get_schema_version`
   (inherits the nil default, like the other ten model-less flavors). The
   **shared ext grammar requires a `doctype`** — `fetch_doctype` always emits
   one (`standard`; `technical-specification`/`technical-report` for the
   `EVS-TS`/`EVS-TR` faces), or Jing fails on `relaton-evs-compile.rng`.

### `#root` is the accessor that answers for every form

A `NationalAdoption` (`EVS-EN ISO 9001:2015/A1:2024`) holds the origin
standard's number and year behind its `base` chain (base = the CEN/CENELEC
document; `AdoptedEuropeanNorm#adopted` = the ISO document; `#root` recurses),
so the year, number and part are read from `#root`. An `InternationalAdoption`
(`EVS-ISO 9001:2015`) or `EstonianStandard` (`EVS 945:2023`) is its own root.

### `Docidentifier` — the year rule

`Relaton::Evs::Docidentifier` (`model/docidentifier.rb`, `< Bib::Docidentifier`)
parses its `content` into `@pubid` (DATA side: lazy `require "pubid"`, rescues
`LoadError`/`StandardError`; a foreign value stays verbatim with `@pubid` nil).
`Pubid#exclude` returns a **copy**, so each mutator replaces `@pubid` and
re-renders through the aliased `store_content`. **`remove_date!` drops the
LAST year**: on a supplement (`EVS-EN ISO 9001:2015/A1:2024`) the supplement's
year goes first (`exclude(:supplement_year)` → `…/A1`), the base year only
when there is none. `to_all_parts!` wraps in pubid's `AllParts` — `content`
stays the part-and-date-stripped string on purpose; `#pubid` renders the
"(all parts)" marker.

### Printed separator is identity

`EVS EN 18216:2026` (space) and `EVS-EN 18216:2026` (hyphen) parse to the same
class and root, but each renders back **as written** — pubid preserves the
input's separator. Never compare EVS identifiers by `to_s`; compare by parse
(`===`, `root.number`).

### Registration

`Processor` (`processor.rb`) sets `@short = :relaton_evs`, `@prefix = "EVS"`,
`@pubid_flavor = :Evs` (prefixes sourced from `Pubid::Evs.prefixes`) and
`@defaultprefix = %r{^EVS[\s-]}`. It lazy-`require_relative`s `../evs` inside
each method, like every other flavor (`spec/relaton/lazy_loading_spec.rb`
guards that). `lib/relaton.rb` autoloads `:Evs`; `Db::Registry::SUPPORTED_GEMS`
lists `relaton/evs`; `grammar/relaton-evs(-compile).rng` mirrors the CEN pair
(the shared `biblio-standoc` ext already models doctype/flavor/ics/
structuredidentifier, and its `DocRelationType` carries `adoptedFrom`).
