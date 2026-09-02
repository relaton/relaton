# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-ogc is a Ruby gem for retrieving and managing OGC (Open Geospatial Consortium) Standards metadata. It is part of the Relaton ecosystem for bibliographic data management. The gem implements the OGC flavor on top of `relaton-iso`, which itself builds on `relaton-bib`.

## Commands

```bash
# Install dependencies
bundle install

# Run all tests
bundle exec rspec

# Run a single test file
bundle exec rspec spec/relaton/ogc/item_spec.rb

# Run a single test by line number
bundle exec rspec spec/relaton/ogc/item_spec.rb:7

# Lint
bundle exec rubocop

# Lint with auto-correct
bundle exec rubocop -A

# Interactive console
bin/console

# Build and install gem locally
bundle exec rake install
```

## Architecture

### Class Hierarchy

All model classes use `Lutaml::Model::Serializable` for XML/YAML serialization with declarative attribute and mapping definitions.

```
Iso::Item (from relaton-iso)
└── Relaton::Ogc::Item          # serializer, extends Iso::Item with `ext` and `docidentifier`
    ├── Relaton::Ogc::Bibitem   # includes Bib::BibitemShared
    └── Relaton::Ogc::Bibdata   # includes Bib::BibdataShared

Bib::ItemData (from relaton-bib)
└── Relaton::Ogc::ItemData      # data model returned by Item.from_xml / Item.from_yaml
```

- **Item** (`lib/relaton/ogc/item.rb`) — serializer; extends `Iso::Item`, declares `model ItemData`, adds `ext` (Ext) and `docidentifier` (Docidentifier) attributes
- **ItemData** (`lib/relaton/ogc/item_data.rb`) — plain data model extending `Bib::ItemData`
- **Ext** (`lib/relaton/ogc/ext.rb`) — OGC extension data: doctype, subdoctype (with constrained values)
- **Doctype** (`lib/relaton/ogc/doctype.rb`) — enumerated OGC document types (standard, engineering-report, best-practice, etc.)
- **Docidentifier** (`lib/relaton/ogc/docidentifier.rb`) — parses its `content`
  into a `Pubid::Ogc::Identifier` exposed as `#pubid`; see **Pubid-backed
  docidentifier**
- **Bibitem** / **Bibdata** — thin wrappers mixing in shared serialization behavior from `relaton-bib`

### Search & Fetch Pipeline

- **Bibliography** (`lib/relaton/ogc/bibliography.rb`) — entry point: `search(text)` and `get(code, year, opts)`
- **HitCollection** (`lib/relaton/ogc/hit_collection.rb`) — fetches from the `relaton-data-ogc` repo (`v2` branch) and resolves the reference against the index; see **Index (`index-v2`, pubid-keyed)**
- **Hit** (`lib/relaton/ogc/hit.rb`) — wraps a single search result; lazy-fetches `ItemData` on `#item`
- **Processor** (`lib/relaton/ogc/processor.rb`) — `Core::Processor` implementation for Relaton registry integration

### Pubid-backed docidentifier

`Relaton::Ogc::Docidentifier` parses its `content` into a
`Pubid::Ogc::Identifier` kept in `@pubid`, while the lutaml `content` attribute
stays a plain **string** for serialization. Parsing is **soft**: `content=`
lazily requires pubid and rescues `LoadError`/`StandardError`, so a missing gem
or non-OGC content leaves `@pubid` nil rather than raising.

It was an empty subclass before, which meant it inherited
`Bib::Docidentifier`'s `remove_part!` / `remove_date!` / `to_all_parts!` — each
of which raises `NotImplementedError`. `Bib::ItemData` broadcasts all three to
every docidentifier (`item_data.rb:74`, `:87`), so `#to_all_parts` and
`#to_most_recent_reference` **raised on every OGC item**, and because
`NotImplementedError` descends from `ScriptError` a caller's `rescue => e` did
not catch it. The mapping is OGC-specific:

- **`remove_date!` → clears `revision`.** OGC carries no date component;
  `revision` is its version discriminator — the same component
  `HitCollection#ignored` treats as omittable — so clearing it yields the
  version-agnostic ("most recent") reference: `12-128r19` → `12-128`.
- **`year` is never cleared.** It looks date-like but is half the document
  number (`12-128`), not a publication qualifier; dropping it would leave
  `-128`, which identifies nothing.
- **`remove_part!` → clears the (unused) `part`/`subpart`.** A no-op for the
  rendered string today — OGC models no part — but implemented so it never
  raises, and it starts working if pubid-ogc ever adds one. (The IALA
  precedent.)
- **`to_all_parts!` → both, plus `all_parts`** behind a `respond_to?` guard;
  the OGC renderer emits no marker for it, so the stripped id is the best
  available rendering.

`refresh_content!` renders a bare `to_s`. The OGC printed form carries no
publisher token and the stored `content` does not either, so — unlike 3GPP,
whose `refresh_content!` must pass `with_publisher: true` — this one must not.

### Index (`index-v2`, pubid-keyed)

`INDEXFILE` is the pubid-backed `index-v2`: rows are `Pubid::Ogc::Identifier`
hashes (`_type: pubid:ogc:document` with `year`/`number`/`revision`). Every
index call site — `HitCollection#index`, `DataFetcher#index`,
`Processor#remove_index_file` — passes
`pubid_class: ::Pubid::Ogc::Identifier`. That is what makes `Relaton::Index`
deserialize the rows into identifiers, sort them by `id.root.number`, and let
`Type#search` bsearch. Omitting it on the **producer** side writes v1-shaped
rows under a v2 name, silently (`FileIO#save` only calls `to_hash` when the
value is an instance of `pubid_class`); omitting it on the **consumer** side
leaves the rows raw hashes with `FileIO#sorted` false, so every lookup scans
all ~1,258 rows.

`HitCollection#best_match` follows the ETSI/W3C/IALA idiom:

- **Pass the pubid, not the string.** `Type#search_candidates` narrows only
  when the argument is not a `String`, so passing the reference text — which
  this flavor used to do — disables the binary search however the index was
  built. `pubid_class:` alone fixes nothing; both had to change together.
- **Ignore what the reference omits.** `revision` is OGC's only optional
  component, so a bare `OGC 12-128` finds the `r19` row through
  `ignore: %i[revision]`.
- **`year` is never ignorable.** The bsearch key is the `<nnn>` field alone, so
  one bucket holds every year that reused the number — `05-015`, `08-015r2`,
  `26-015r1` all sit in bucket `015` (179 buckets, largest 20). `year` is what
  tells them apart.
- **An unparseable reference still searches**, by the previous full-scan
  substring match on `id.to_s`.

#### Ordering: latest revision wins

`min_by { |r| r[:id] }` compared raw strings, so a bare `12-128` returned
`r10` — `"r10" < "r14"` as text. The key is now the revision, with its number
compared **as an integer** (`r19` beats `r2`) and the token itself breaking the
tie (`r3a` above `r3`, `r12a` above `r12`), because the index sort is not
stable.

Scored against each document's own `date[0].at` over the 106 multi-revision
documents in the published index:

| Key | Picks the newest published document |
|---|---|
| revision number, numeric | 105/106 — **99%** |
| the old `min_by { r[:id] }` | 1/106 — **1%** |

Only 106 of 1,110 documents carry more than one revision, so the change is
narrow — but for those it was returning the oldest revision almost every time.

#### Two ids that do not round-trip

Measured over all 1,258 published rows, 1,256 render back byte-identically. The
two that do not are **data defects upstream**, which pubid canonicalizes:
`"20-001r2 "` (trailing space) and `"11-038R2"` (uppercase revision). Migrating
fixes both — the v2 rows store the canonical form — so a lookup of either
spelling now resolves. Do not "fix" them by special-casing the parser.

#### Verified against the published index

`relaton-data-ogc` publishes `index-v2.zip`. Loaded through
`HitCollection#index`: 1,258 rows, all deserialized to identifiers, sorted, **0**
keying on `""`, and a `12-128` lookup narrows to **11 of 1,258**. Live fetches
resolve every shape the flavor has to handle — a bare `OGC 12-128` → `r19`
(2024-02-06), an explicit `12-128r14` → 2017, the letter-suffixed `12-128r12a`,
the two upstream data defects (`11-038R2`, `20-001r2`), the revision-less
`16-079`, both sides of the shared `015` bucket (`05-015` and `26-015r1`), and a
reference with no `OGC ` token.

The published rows are byte-for-byte what this gem's `DataFetcher` writes: when
the fixture was still being converted from `index-v1` locally, the converted set
and the published one held the same 1,258 rows.

### Data Fetching

- **DataFetcher** (`lib/relaton/ogc/data_fetcher.rb`) — bulk-fetches OGC documents from the NamingAuthority JSON endpoint
- **Scraper** (`lib/relaton/ogc/scraper.rb`) — parses individual OGC document JSON into `ItemData`

### Key Dependencies

- `relaton-iso` — provides `Iso::Item` base class and ISO bibliographic structures
- `relaton-bib` (transitive via relaton-iso) — core types: `Bib::ItemData`, `Bib::Doctype`, `Bib::Ext`, etc.
- `lutaml-model` (transitive) — serialization framework for XML/YAML mapping
- `faraday` — HTTP client for fetching remote data
- `relaton-index` — index-based document lookup from GitHub-hosted data repos

### Serialization Pattern

Models declare attributes and XML mappings in the same class. `Item` is the serializer (handles `from_xml`, `from_yaml`, `to_xml`), `ItemData` is the plain data object returned. Round-trip fidelity (parse → serialize → parse) is the primary correctness criterion tested in specs.

### Test Setup

- **RSpec** with `--format documentation`
- **VCR** + **WebMock** for HTTP interaction recording (`spec/vcr_cassettes/`)
- **Jing** for RelaxNG schema validation against `grammars/relaton-ogc-compile.rng`
- **equivalent-xml** for XML comparison in tests
- Fixtures live in `spec/fixtures/` (YAML, XML)
- Integration tests in `spec/relaton/ogc/integration_spec.rb` exercise the full search → fetch → serialize pipeline

### Grammars

RelaxNG schemas in `grammars/` define the valid XML structure. `relaton-ogc-compile.rng` is the combined schema used for test validation.

### API Notes

- `Bib::Docidentifier` uses `.content` (not `.id`) for the identifier string
- `Bib::Date` uses `.at` returning a `StringDate::Value`; parse with `::Date.parse(d.at.to_s)` to extract year

## Linting

RuboCop inherits from the [Ribose OSS style guide](https://github.com/riboseinc/oss-guides). Target Ruby version is 3.1. Rails cops are loaded but disabled.

## CI

GitHub Actions workflows in `.github/workflows/` are auto-generated by Cimas — avoid manual edits. `rake.yml` runs tests on push/PR; `release.yml` handles gem publishing.

## Testing

- Run the suite with `bundle exec rake spec:ogc` from the repo root; specs live
  in `spec/ogc/` and run self-contained (see the root `CLAUDE.md`).
- **Index fixture:** `spec/ogc/fixtures/index-v2.zip` is seeded into the
  `Relaton::Index` pool by `spec/ogc/support/webmock.rb` — in `before(:each)`,
  not only `before(:suite)`, because `Index::Pool#type` replaces the pooled
  entry whenever `actual?` says no and `DataFetcher#index` asks for the same
  type without a `url:`. The pool key is `type.upcase.to_sym`, so the flavor's
  `:ogc` is pooled as `:OGC`. It is built **with `pubid_class:`**; without it
  the suite would pass while exercising something the runtime never does.
- Refresh it with `bundle exec rake spec:update_index_ogc`. Unlike 3GPP's, this
  fixture is the whole published index (~1,258 rows) rather than a curated
  subset — small enough that keeping all of it costs nothing. Rows are copied
  **verbatim** from the published `index-v2.zip`; `#build` refuses a v1 source
  rather than writing a fixture `Relaton::Index` would reject wholesale.
