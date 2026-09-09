# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is relaton-xsf?

A Ruby gem for bibliographic retrieval of XMPP XEP (XMPP Extension Protocol) specifications. Part of the Relaton family of gems. Fetches data from https://xmpp.org/extensions/refs/ and the relaton-data-xsf GitHub repository.

## Commands

- `bundle exec rake spec:xsf` — run this flavor's suite (from the repo root)
- `bundle exec rake spec:update_index_xsf` — refresh
  `spec/xsf/fixtures/index-v2.zip` from the published index
- `bundle exec rubocop` — lint
- `bundle exec rubocop -a` — lint with auto-fix
- `bin/console` — interactive console with gem loaded

## Architecture

Namespace: `Relaton::Xsf` (under `lib/relaton/xsf/`). Branch `lutaml-integration` uses the new nested namespace (not the old `RelatonXsf`).

Key classes and their base classes from relaton-core:

| Class | Base | Role |
|---|---|---|
| `Processor` | `Relaton::Core::Processor` | Plugin entry point for relaton registry |
| `Bibliography` | Module (extends self) | Search & get interface (`search`, `get`) |
| `HitCollection` | `Relaton::Core::HitCollection` | Collection of search results |
| `Hit` | `Relaton::Core::Hit` | Single result; lazy-loads YAML from GitHub |
| `DataFetcher` | `Relaton::Core::DataFetcher` | Crawls xmpp.org, parses BibXML, saves docs |
| `Item` / `Bibitem` / `Bibdata` | `Relaton::Bib::Item` | Bibliographic item models (lutaml-model based) |

## Index (`index-v2`, pubid-keyed)

`INDEXFILE` is the pubid-backed `index-v2`: rows are `Pubid::Xsf::Identifier`
hashes (`_type: pubid:xsf:xep` with `number`). All three index call sites —
`HitCollection#index`, `DataFetcher#index`, `Processor#remove_index_file` —
pass `pubid_class: ::Pubid::Xsf::Identifier`. Omitting it on the **producer**
writes v1-shaped rows under a v2 name, silently (`FileIO#save` calls `to_hash`
only for instances of `pubid_class`); omitting it on the **consumer** leaves
the rows raw hashes with `FileIO#sorted` false, so every lookup scans all 518.

An XEP identifier is a publisher and a number, nothing else — no edition, no
date, no part, and one row per XEP (518 rows, ids unique). That makes this the
simplest flavor in the sweep: there is no selection order to preserve and
nothing is ignorable in `matches?`, so lookup is exact equality after
narrowing.

### The two non-documents, and why the guard is not optional

The crawled source carries the XMPP repo's `README` and its `xep-xxxx`
template, which reach the indexer as the docids `XEP README` and `XEP xxxx`.
pubid rejects both.

One unparseable row does not fail that row. `Relaton::Index` declares the
**whole file** corrupt, deletes it, and hands back an **empty** index —
measured: 518 good rows plus a single `XEP README` loads as **0 rows**, and the
only trace is two INFO lines (`Wrong structure of file …`, `Considering …
corrupt, removing it`). So indexing either one silently breaks every XSF
lookup, not just those two.

`DataFetcher#add_to_index` therefore parses the docid and, on failure, records
`@errors[docid]` — which `report_errors` turns into a GitHub issue at the end
of the crawl (the 3GPP/ECMA precedent) — and skips the row. The data file is
still written, so the document is unindexed, never lost.

### Lookup

`HitCollection#search` follows the ETSI/W3C/OGC idiom:

- **Pass the pubid, not the string.** `Type#search_candidates` narrows only
  when the argument is not a `String`, so the plain reference this flavor used
  to pass disabled the binary search however the index was built.
  `pubid_class:` alone fixes nothing; both had to change together.
- **Matching is exact.** The old `index.search(ref)` compared a **substring**
  of the rendered id, so a bare `001` answered with **11** documents
  (`XEP 0001` and every `XEP 001x`) and `Bibliography#get` took `.first` —
  a truncated reference silently resolved to whichever sorted first. It now
  returns nothing.
- **Three reference forms are normalized** in `#normalize_ref`, because
  `Pubid::Xsf` accepts only the canonical `XEP 0001`:

  | form | before | after |
  |---|---|---|
  | `XEP 0001` | resolves | resolves |
  | `0001` (bare) | resolves (substring) | resolves — the token is added |
  | `XEP-0001` | **no match** | resolves — the spelling xmpp.org itself uses |
  | `xep 0001` | no match | resolves — the token match is case-insensitive |

  The hyphen and case forms are new support, not preserved behaviour: the
  substring match compared against `XEP 0001`, which has a space.

### The v1 window

`relaton-data-xsf` publishes `index-v1.zip` only until it re-crawls with a
`relaton` carrying this change, so live XSF lookups are broken in that window —
exactly as they were for W3C, 3GPP and OGC. The spec fixture does not depend on
it: `tasks/index_fixture_xsf.rb` converts the published v1 rows through pubid
and drops the same two non-documents the producer skips.

After the re-crawl that repo publishes **both** indexes from one crawl: the
`index-v2` this fetcher writes (518 rows), and its own `index-v1` (520 rows)
built from the crawled documents in `data/` by `build_index_v1.rb`. It builds v1
from `data/` rather than deriving it from v2 precisely so `XEP README` and
`XEP xxxx` survive for released consumers while staying out of v2.

Data flow: `Processor#get` → `Bibliography.get` → `HitCollection.search` → `Hit#item` → fetches YAML → `Relaton::Bib::Item.from_yaml`

DataFetcher flow: Crawls `https://xmpp.org/extensions/refs/`, parses each XML ref via `Relaton::Bib::Converter::BibXml.to_item`, sets `ext.flavor = "xsf"`, saves to disk.

Constants: `INDEXFILE = "index-v2"`, `GHDATA_URL` points to relaton-data-xsf `v2` branch.

## Testing

- **Index fixture:** `spec/xsf/fixtures/index-v2.zip` is seeded into the
  `Relaton::Index` pool by `spec/xsf/support/webmock.rb` — see **Index
  (`index-v2`, pubid-keyed)** above for why it is re-seeded per example and
  built with `pubid_class:`. Refresh it with `rake spec:update_index_xsf`.
- RSpec with VCR cassettes (`spec/vcr_cassettes/`) for HTTP interactions
- WebMock disables all external network connections
- Fixtures in `spec/fixtures/` (item.yaml, bibdata.xml, bibitem.xml)
- Round-trip tests verify YAML→Item→YAML and XML→Item→XML fidelity
- `DataFetcher` is lazily required — specs that test it must `require "relaton/xsf/data_fetcher"` explicitly
- Same for `Processor` — `require "relaton/xsf/processor"`

## Key dependencies

- `relaton-core` — abstract base classes (Processor, HitCollection, Hit, DataFetcher)
- `relaton-bib` — bibliographic models, XML/YAML serialization (lutaml-model based)
- `relaton-index` — index management for quick document lookups
- `mechanize` — HTTP fetching and HTML parsing

## Style

- RuboCop with relaton shared config (inherits from riboseinc/oss-guides)
- Target Ruby version: 3.1
- Logging via `Relaton::Xsf::Util` (extends `Relaton::Bib::Util`, PROGNAME = "relaton-xsf")
