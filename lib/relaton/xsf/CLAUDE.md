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
| `Bibliography` | Module (extends self) | Search & get interface; **parses the reference into a pubid** (`parse_ref`) |
| `HitCollection` | `Relaton::Core::HitCollection` | Collection of search results |
| `Hit` | `Relaton::Core::Hit` | Single result; lazy-loads YAML from GitHub |
| `DataFetcher` | `Relaton::Core::DataFetcher` | Crawls xmpp.org, parses BibXML, saves docs |
| `Docidentifier` | `Relaton::Bib::Docidentifier` | Exposes the id as a `Pubid::Xsf::Identifier` via `#pubid` |
| `Item` / `Bibitem` / `Bibdata` | `Relaton::Bib::Item` | Bibliographic item models (lutaml-model based) |

## Index (`index-v2`, pubid-keyed)

`INDEXFILE` is the pubid-backed `index-v2`: rows are `Pubid::Xsf::Identifier`
hashes (`_type: pubid:xsf:xep` with `number`). All three index call sites —
`HitCollection#index`, `DataFetcher#index`, `Processor#remove_index_file` —
pass `pubid_class: ::Pubid::Xsf::Identifier`. Omitting it on the **producer**
writes v1-shaped rows under a v2 name, silently (`FileIO#save` calls `to_hash`
only for instances of `pubid_class`); omitting it on the **consumer** leaves
the rows raw hashes with `FileIO#sorted` false, so every lookup scans all 520.

An XEP identifier is a publisher and a number, nothing else — no edition, no
date, no part, and one row per XEP (520 rows, ids unique). That makes this the
simplest flavor in the sweep: there is no selection order to preserve and
nothing is ignorable in `matches?`, so lookup is exact equality after
narrowing.

### The index guard, and the two rows that are pages rather than XEPs

`DataFetcher#add_to_index` parses the docid and, on failure, records
`@errors[docid]` — which `report_errors` turns into a GitHub issue at the end of
the crawl (the 3GPP/ECMA precedent) — and skips the row. The data file is still
written, so a document that cannot be indexed is unindexed, never lost.

The guard is not decoration. One unparseable row does not fail that row:
`Relaton::Index` declares the **whole file** corrupt, deletes it, and hands back
an **empty** index — measured, 519 good rows plus one unparseable id loads as
**0 rows**, and the only trace is two INFO lines (`Wrong structure of file …`,
`Considering … corrupt, removing it`). Every XSF lookup then fails silently.

Two published rows are pages rather than XEPs — the XMPP repository's `README`
and its `xep-xxxx` template, which the crawl mints records for because they sit
in the same listing. pubid accepts them as the literal numbers `README` and
`xxxx`, so they carry into `index-v2` like any other row and resolve normally.
It stayed strict about everything else: `XEP banana` and a typo such as
`XEP 00O1` are still rejected, which is what keeps an unparseable reference a
warning rather than a silent miss.

Nothing in the published corpus trips the guard today, so a recorded error means
upstream grew a shape pubid does not know — exactly when an issue is worth
filing.

### Where the reference becomes an identifier

`Bibliography.parse_ref` does it, not `HitCollection`. That split is not
cosmetic: `Type#search_candidates` narrows only when its search argument is
**not** a `String`, so the string has to become an identifier at the entry
point. `HitCollection` therefore receives a `Pubid::Xsf::Identifier` (or nil,
when the reference could not be parsed) and does nothing but the index lookup.
`Core::HitCollection` documents `ref` as `[String, Pubid]`, so this is the
interface working as intended.

### Pubid-backed docidentifier

`Relaton::Xsf::Docidentifier` parses its `content` into a
`Pubid::Xsf::Identifier` kept in `@pubid`, while the lutaml `content` attribute
stays a plain string. Parsing is soft — a missing gem or non-XSF content leaves
`@pubid` nil rather than raising during deserialization. `Item` narrows the
inherited `docidentifier` attribute to it.

It is **purely additive**: `to_yaml` and `to_xml` are byte-identical before and
after, so no published document or index needs regenerating.

**It deliberately implements none of `remove_part!` / `remove_date!` /
`to_all_parts!`.** An XEP identifier is a publisher and a number and nothing
else, so there is genuinely nothing for any of them to strip, and
`Bib::Docidentifier` defaults all three to no-ops for exactly that case. Empty
overrides would assert a flavor rule that does not exist. Compare
`Relaton::Ogc::Docidentifier`, which overrides `remove_date!` because OGC really
does carry a revision.

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
- **An unrecognized reference raises.** Like ISO, ETSI and 3GPP, the parse
  error propagates: relaton-cli rescues `Parslet::ParseFailed` and renders
  `"..." is not a recognized standards identifier`
  (`gems/relaton-cli/lib/relaton/cli/command.rb:324`,
  `subcommand_collection.rb:134`), and `Db#fetch` logs it through the
  `StandardError` arm at `lib/relaton/db.rb:122`. `Pubid::Errors::ParseError`
  **is** a `Parslet::ParseFailed`, which is what makes the CLI's rescue work
  for every flavor.

  Rescuing into a warning and an empty result — which several flavors still do
  — collapses "this identifier is malformed" into "no such document", and a
  caller cannot tell them apart. The parse also happens **before**
  `HitCollection` is constructed, so it is never relabelled as the
  `Relaton::RequestError` that collection's own rescue raises.
- **Three reference forms are normalized** in `Bibliography#normalize_ref`, because
  `Pubid::Xsf` accepts only the canonical `XEP 0001`:

  | form | before | after |
  |---|---|---|
  | `XEP 0001` | resolves | resolves |
  | `0001` (bare) | resolves (substring) | resolves — the token is added |
  | `XEP-0001` | **no match** | resolves — the spelling xmpp.org itself uses |
  | `xep 0001` | no match | resolves — the token match is case-insensitive |

  The hyphen and case forms are new support, not preserved behaviour: the
  substring match compared against `XEP 0001`, which has a space.

### Both indexes, one crawl

`relaton-data-xsf` publishes **both** from a single crawl: the `index-v2` this
fetcher writes, and its own `index-v1` built by `build_index_v1.rb` for released
relaton v2 consumers. Both carry the same 520 rows — building v1 from `data/`
was originally what kept `XEP README` and `XEP xxxx` available there while they
were unindexable in v2, and pubid accepting them has since removed that
asymmetry.

Verified against the published `index-v2`: 520 rows, all deserialize, sorted,
**0** keying on `""`, `XEP 0001` narrows to 1 of 520, and every accepted
spelling resolves to a file that returns HTTP 200.

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
