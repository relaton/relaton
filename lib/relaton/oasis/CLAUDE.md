# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-oasis is a Ruby gem for retrieving and serializing OASIS Standards bibliographic metadata. It is part of the Relaton family of gems and implements the IsoBibliographicItem model for OASIS standards. Uses the lutaml-model pattern on the `lutaml-integration` branch.

## Commands

```bash
bundle exec rake spec       # Run all tests (default rake task)
bundle exec rake rubocop    # Run linter
bundle exec rspec           # Run tests directly
bundle exec rspec spec/relaton/oasis/bibitem_spec.rb  # Run a single test file
bin/console                 # Interactive IRB with gem loaded
```

## Architecture

### Class Hierarchy (under `Relaton::Oasis`)

All model classes use the lutaml-model pattern from `relaton-bib`:

- **ItemData** (`lib/relaton/oasis/item_data.rb`) — Data model class extending `Bib::ItemData`
- **Item** (`lib/relaton/oasis/item.rb`) — Base class extending `Bib::Item`, uses `ItemData` model, adds `ext` attribute of type `Ext`
- **Bibitem** (`lib/relaton/oasis/bibitem.rb`) — Extends `Item`, includes `Bib::BibitemShared` for individual bibliography entries
- **Bibdata** (`lib/relaton/oasis/bibdata.rb`) — Extends `Item`, includes `Bib::BibdataShared` for complete bibliography records
- **Ext** (`lib/relaton/oasis/ext.rb`) — Extends `Bib::Ext`, OASIS-specific metadata: `doctype`, `technology_area`, `schema_version`
- **Doctype** (`lib/relaton/oasis/doctype.rb`) — Extends `Bib::Doctype`, valid values: `specification`, `memorandum`, `resolution`, `standard`
- **Docidentifier** (`lib/relaton/oasis/docidentifier.rb`) — Extends
  `Bib::Docidentifier`, parses its `content` into a `Pubid::Oasis::Identifier`
  exposed as `#pubid`; see **Identifiers and the index**

### Bibliography (under `Relaton::Oasis`)

- **Bibliography** (`lib/relaton/oasis/bibliography.rb`) — Module with `search`/`get` class methods for fetching OASIS standards from the relaton-data-oasis GitHub repository. Delegates to private methods: `find_index_entry`, `fetch_yaml`, `parse_item`

### Data Fetching (under `Relaton::Oasis`)

These classes scrape https://www.oasis-open.org/standards/ to produce YAML/XML data files. Loaded separately via `require "relaton/oasis/data_fetcher"`.

- **DataFetcher** (`lib/relaton/oasis/data_fetcher.rb`) — Extends `Core::DataFetcher`, orchestrates fetching all OASIS standards
- **DataParser** (`lib/relaton/oasis/data_parser.rb`) — Parses individual OASIS document nodes into `ItemData`
- **DataPartParser** (`lib/relaton/oasis/data_part_parser.rb`) — Parses multi-part OASIS document nodes into `ItemData`
- **DataParserUtils** (`lib/relaton/oasis/data_parser_utils.rb`) — Shared module included by both parsers; provides contributor parsing, docid construction, retry logic, and doctype detection

### Identifiers and the index

#### Pubid-backed docidentifier

`Relaton::Oasis::Docidentifier` parses its `content` into a
`Pubid::Oasis::Identifier` kept in `@pubid`, while the lutaml `content`
attribute stays a plain **string** for serialization. Parsing is **soft**:
`content=` lazily requires pubid and rescues `LoadError`/`StandardError`, so a
missing gem or non-OASIS content leaves `@pubid` nil rather than raising. The
stored content carries the `OASIS ` publisher token, which is
`Pubid::Oasis::Identifier#to_s`'s default rendering, so a bare slug
(`"amqp-core"`) is *not* an OASIS printed id and leaves `@pubid` nil.

The scrapers still compose the slug by hand (`DataParserUtils#parse_docid`,
`#parse_spec`, `#parse_part`, `#parse_errata`, `DataParser#title_to_docid`) —
pubid parses the result, it does not replace those heuristics.

**`remove_part!` / `remove_date!` / `to_all_parts!` stay the inherited no-ops,
deliberately.** `Pubid::Oasis::Renderer` echoes the verbatim slug held in
`original`, so clearing `part`, `version` or `stage` cannot change the printed
id — the mutation would be invisible — and rewriting `original` would invent a
reference form OASIS does not publish. OASIS slugs are free-form with an
inconsistent internal structure, and no OASIS citation drops a part or a
version; there is no "all parts" or "most recent" spelling to render. Since
`dfbd26c72` those defaults are no-ops rather than `NotImplementedError` raises,
so `Bib::ItemData#to_all_parts` and `#to_most_recent_reference` return the item
unchanged instead of blowing up. Do not "finish" this class by adding them.
(Contrast `Relaton::Ogc::Docidentifier`, whose components really do render.)

#### `index-v2`, written and read

`INDEXFILE = "index-v2"` is the only index this flavor touches: pubid-keyed
rows (`_type: pubid:oasis:standard`), published by `relaton-data-oasis` on its
`v2` branch — the same branch `Bibliography::ENDPOINT` reads.

The producer and the consumer pass `pubid_class: ::Pubid::Oasis::Identifier`:

| Call site | Why it needs `pubid_class:` |
|---|---|
| `DataFetcher#index` | `FileIO#save` calls `to_hash` only for instances of it — without it the crawl writes v1-shaped rows under a v2 name, silently |
| `Bibliography#index` | without it the rows stay raw hashes, `FileIO#sorted` is false, and every lookup scans all 605 rows |

`Processor#remove_index_file` passes `url: true` and `file:`, and no
`pubid_class:`: the delete never reads the index (see
`lib/relaton/index/CLAUDE.md`). It used to omit `url: true`, so `Db#clear` on an
empty pool deleted `./index-v2.yaml` in the working directory and kept the
cache.

`Bibliography#index` also passes `file:`, which the pre-migration code omitted.
`file:` names the cache file (`Type` falls back to `index.yaml` without it), so
the consumer and `remove_index_file` must pass the same one, or `Db#clear`
leaves the consumer's cache in place.

**This gem never writes `index-v1`.** `relaton-data-oasis`'s crawler derives it
from the v2 rows, for relaton v2 consumers only.

#### Resolving a reference

`Bibliography#find_index_entry` is the pubid `best_match` shape:

- **`#parse_ref` supplies the publisher token.** An OASIS printed id starts
  with `OASIS `, and pubid's grammar requires it, but callers write bare slugs
  (`mqtt-v5.0`) and `Db#fetch` passes the reference through verbatim. Adding
  the token is normalization, not identification, so it happens in the flavor —
  the same place W3C normalizes a URL or a leading `TR-`.
- **The parsed pubid is passed to `Type#search`, never the string.** Search
  narrows only for a non-`String` argument, so passing text would disable the
  binary search however the index was built. `pubid_class:` alone fixes
  nothing; both had to change together.
- **`#ignored` ignores exactly what the reference omitted** (`version`,
  `stage`, `part`, `label` — the ETSI/W3C/OGC idiom). `number` is never
  ignorable: it is the specification name, the whole identity of an OASIS
  record and the key the index bsearches on.
- **There is no substring fallback.** After normalization the only unparseable
  inputs are a blank string and one over pubid's 1000-character cap, and a
  substring scan for `""` matches every row — worse than a miss. An
  unparseable reference warns and returns nil.

##### Ordering: `#ranking_key`

Ignoring a component means "don't care", so a loose reference also matches the
more specific rows. The key, in order: an **exact printed id**; then the
**newest version**, segments compared as integers; then the **least specific**
row; then the **later stage revision** (digits only — OASIS stage letters have
no ranking this code may invent); then the printed id, so the result never
depends on index order.

The exact-match rule is not decoration. Five records are a bare specification
name that also has versioned siblings — `OASIS EDXL`, `OData`, `OSLC`, `SAML`,
`WSS` — and without it three of them answered with their newest sibling instead
of themselves. Published ids are unique (0 duplicates in 605 rows), so at most
one row can score there.

Verified over the whole published index: **all 605 ids resolve to their own
record**, with and without the publisher token.

##### One behaviour is deliberately lost

v1 matched by substring, so `OASIS amqp` resolved to some `amqp-core` record.
v2 matches identifiers, so a partial specification name no longer resolves.
That is the same semantic change IANA recorded, and
`spec/oasis/relaton/oasis/bibliography_spec.rb` asserts it so it stays a
decision rather than a surprise.

#### Unparseable ids are reported, in two places on purpose

`DataFetcher#add_to_index` indexes `docid.pubid` and, when it is nil, records
the reason in `@errors` and skips the row rather than indexing it unparsed:
`Relaton::Index` rejects the WHOLE index if a single row fails to deserialize,
and its sort calls `.root.number` on every id. The data file is still written,
so a document is unindexed, never lost.

`DataParserUtils#record_unparseable_id` records the **same** thing at the moment
the id is built. That is not redundant: the part ids that only ever become a
relation's `formattedref` (`DataParser#parse_relation`,
`DataPartParser#parse_relation`) never reach `save_doc`, so an index-time hook
alone cannot see them. Both entries are keyed on the **id string**, so a
document that is saved reports one line — the fetcher's, which also names the
output file. Keep the two keys identical.

Both routes rely on `Core::DataFetcher#report_errors` treating a **String**
value in `@errors` as the message, logged verbatim at `:error`, which is the
level the `GhIssue` channel subscribes to. So each entry becomes one line of the
crawl's "Error fetching documents" GitHub issue, and the key serves only to
de-duplicate. W3C and 3GPP use exactly this `@errors` route; ISO, ITU and NIST
reach the same issue through a side list plus a `report_errors` override.
OASIS is the only flavor that also records from its parser, for the
`formattedref` reason above.

#### The index key

`Index::Type#candidates_by_number` bsearches on `id.root.number.to_s`, and
`FileIO` sorts by that same key. `Pubid::Oasis::Identifier#number` holds the
**specification name** — "OSLC-CoreShapes", "STIX", "amqp-core" — so every
version, stage and part of one specification shares a bucket, the same shape as
an IETF draft slug or an IANA registry slug.

This needed a pubid change: the attribute was called `spec` and `number` was
never set, so every row keyed on `""` — one bucket, bsearch degraded to a
linear scan, silently, exactly the IANA and W3C trap. pubid `cfe8ee84` renames
it, with **no alias**, and it ships in the released `2.0.0.alpha.10` that
`relaton.gemspec` pins — so this flavor needs nothing from the `Gemfile`'s
temporary pubid `main` pin, unlike the nine listed there.
`spec/oasis/relaton/oasis/pubid_contract_spec.rb` is the standing guard: it
fails against any pubid that does not set `number`.

The flavor is indifferent to pubid's parse-failure class, which moved twice
during this work — `RuntimeError`, then `Parslet::ParseFailed`, and in
alpha.10 `Pubid::Errors::ParseError` (a `Parslet::ParseFailed`) with
`Pubid::Errors::InvalidInputError` (an `ArgumentError`) for a non-String or an
over-long input. `Docidentifier#content=` and `Bibliography#parse_ref` both
rescue `StandardError`, which every one of those descends from.

Measured over all 605 published rows, written through
`Relaton::Oasis::Docidentifier` into a `pubid_class:`-configured index and read
back: 605 rows round-trip byte-identically, 0 unparseable, 0 keying on `""`,
309 buckets with the largest 25, and a `STIX` lookup narrows to 25 of 605.

### Serialization

Supports XML (with RELAX NG schema validation via `grammars/`) and YAML round-trip serialization. Classes use `from_xml`/`to_xml` and `from_yaml`/`to_yaml` class methods inherited from the lutaml-model base.

### Test Conventions

Tests are round-trip based: parse a fixture file, serialize back, and compare output to input. XML tests also validate against the RELAX NG schema (`../../grammar/relaton-oasis-compile.rng`) using the `ruby-jing` gem — so the suite needs a Java runtime on `PATH`. Fixtures live in `spec/oasis/fixtures/`. VCR cassettes record HTTP interactions in `spec/oasis/vcr_cassettes/`. Private methods are tested via `send(:method_name, ...)`.

## Style

RuboCop config inherits from the Ribose OSS style guide. Target Ruby version: 3.4. Rails cops are required but disabled.

## Testing

Run the suite with `bundle exec rake spec:oasis` from the repo root; specs live
in `spec/oasis/` and run self-contained (see the root `CLAUDE.md`).

- **Index fixture:** `spec/oasis/fixtures/index-v2.zip` — the whole published
  index (605 rows, verbatim), seeded into the `Relaton::Index` pool by
  `spec/oasis/support/webmock.rb` in `before(:each)`, not only
  `before(:suite)`: `Index::Pool#type` replaces the pooled entry whenever
  `actual?` says no, and `DataFetcher#index` asks for the same `:oasis` type
  with a `file:` and no `url:`. One producer example would otherwise evict the
  fixture and send every later consumer example to a real download. The pool
  key is `type.upcase.to_sym`, so `:oasis` is pooled as `:OASIS`.
- It is built **with `pubid_class:`**, and `type.index` runs once offline to
  force the deserialize and sort. Without that the suite would pass while
  exercising something the runtime never does.
- Refresh it with `bundle exec rake spec:update_index_oasis`
  (`tasks/index_fixture_oasis.rb`), which copies the published rows verbatim
  and refuses a v1 source rather than writing a fixture `Relaton::Index` would
  reject wholesale.
- **The fixture must be written with `File.binwrite`.** The zip entry comes
  back `ASCII-8BIT`, and one published row carries a non-breaking space —
  `OpenC2-MQTT-v1.0]<NBSP>-CS01`, a malformed upstream "cite as" that pubid
  keeps verbatim in `original`. `File.write(..., encoding: "UTF-8")`
  transcodes and raises `Encoding::UndefinedConversionError` on it. Same
  invariant as `Index::FileStorage#write`; OGC's copy of this fixture code gets
  away with the transcode only because its rows are pure ASCII.
