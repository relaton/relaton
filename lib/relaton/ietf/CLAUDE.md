# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Gem Does

The `Relaton::Ietf` flavor fetches and parses IETF bibliographic data (RFCs, Internet-Drafts, BCPs, FYIs, STDs) into the Relaton data model. Models are `lutaml-model`-based.

## Commands

The suite runs from its own directory (`spec/ietf/`), as every flavor suite does.

```bash
bundle exec rake spec:ietf                                      # run this flavor's suite
cd spec/ietf && bundle exec rspec -I . relaton/ietf/bibxml_parser_spec.rb  # single file
cd spec/ietf && bundle exec rspec -I . relaton/ietf/rfc/entry_spec.rb:19   # single example
cd spec/ietf && bundle exec rspec -I . -e "creates primary docid"          # by description
bundle exec rubocop                                             # lint
```

## Architecture

### Data Model (Lutaml::Model)

All models use `Lutaml::Model::Serializable` with `attribute` declarations and `xml do ... end` blocks for serialization. The IETF classes extend base `Relaton::Bib` classes:

- `Relaton::Ietf::ItemData < Bib::ItemData` — core bibliographic data
- `Relaton::Ietf::Item < Bib::Item` — adds `ext: Ext` attribute
- `Relaton::Ietf::Bibdata < Item` / `Bibitem < Item` — include shared serialization concerns
- `Relaton::Ietf::Ext` — IETF extensions: `doctype`, `flavor`, `stream`, `area`, `ipr`, `pi`
- `Relaton::Ietf::Doctype` — types: `"rfc"`, `"internet-draft"`

### Namespace Resolution

Converter classes use `Bib::NamespaceHelper` which resolves `namespace` by taking the first two segments of the class name. For `Relaton::Ietf::BibXMLParser::FromRfcxml`, `namespace` returns `Relaton::Ietf`, so `namespace::ItemData` → `Relaton::Ietf::ItemData`, `namespace::Ext` → `Relaton::Ietf::Ext`, etc.

### Key Flows

1. **Single document lookup**: `Processor#get` → `Bibliography.get(code)` → `Scraper.scrape_page` → fetches YAML from GitHub data repos (`relaton-data-rfcs`, `relaton-data-ids`, `relaton-data-rfcsubseries`) via `relaton-index`

2. **Bulk data fetching**: `DataFetcher` extends `Relaton::Core::DataFetcher` with three datasets:
   - `ietf-rfcsubseries` / `ietf-rfc-entries`: parse `rfc-index.xml` via `Rfc::Index` / `Rfc::Entry#to_item`
   - `ietf-internet-drafts`: parse local BibXML files via `BibXMLParser.parse`

3. **BibXML parsing** (`BibXMLParser` module):
   - `parse(xml)` — parses `<reference>` elements via `FromRfcxml` converter
   - `parse_rfc(xml)` — parses `<rfc>` root documents via `FromRfc` converter
   - Converters inherit from `Bib::Converter::BibXml::FromRfcxml` with IETF overrides for contributor/person/org handling

4. **RFC Index parsing** (`Rfc::Entry#to_item`): converts RFC editor index entries (BCP/FYI/STD/RFC) into `ItemData`, handling subseries vs full RFC entries differently

### Converter Inheritance Chain

```
Bib::Converter::BibXml::FromRfcxml    # base: handles <reference> generically
  └── Ietf::BibXMLParser::FromRfcxml  # IETF overrides: publisher, org recognition, person names
        └── Ietf::BibXMLParser::FromRfc  # <rfc> root: uses doc_name instead of anchor, no ref-level series_info
```

`FromRfc` must override all methods that access `@reference.anchor`, `@reference.target`, `@reference.format`, or `@reference.series_info` since `Rfcxml::V3::Rfc` lacks these attributes (unlike `Rfcxml::V3::Reference`).

## Unified index (relaton#109) — producer done, consumer outstanding

The producer and the consumer are on **different index generations**, on purpose:
`DataFetcher` now writes the pubid `index-v2`, while `Scraper` still reads three
plain-string `index-v1` files — `:RFC`, `:RSS`, `:IDS` in `scraper.rb:9-11,40-56`,
one per data repo, branch `v2`. The consumer cannot move until an `index-v2` is
actually published somewhere.

relaton#109 collapses those three into one `relaton/relaton-data-ietf` index.

Decisions taken (2026-08-18 … 2026-08-22):

| | |
|---|---|
| Index structure | **unchanged** — `:id` + `:file` only. No `docids[]`, no summary fields; a third key invalidates the whole index for every released gem |
| `:id` shape | structured pubid hash (`Pubid::Ietf::Identifier#to_hash`), i.e. `index-v2` |
| Row per record | keyed by the record's **primary** docidentifier. A sub-series id resolves to its own container record, *not* to a constituent RFC — 42 of 365 sub-series include more than one RFC, so there is no single document to alias to; consumers follow `relation: includes` |
| DOI ids | omitted — not `pubid:ietf`-representable, and one unparseable row kills the index. Unchanged from today; DOIs are served by the `doi` flavor |
| Who builds it | `DataFetcher`, during the crawl — not a separate pass over the written records, which would be a second answer to "what is this record's id" and could drift from the fetcher's |
| Three type repos | untouched: they pin `relaton/relaton-ietf`, not this monorepo, so they keep emitting `index-v1` |

**The pubid prerequisites are done** (landed 2026-08-20; the asks are recorded in
`/work/HANDOFFS/metanorma__pubid__ietf-index-readiness.md`). Three gaps that each
would have made a `pubid:ietf` index unusable: 50 draft ids didn't parse (the
grammar admitted neither `.` nor uppercase in a slug); the zero-padded `STD0066`
that rfc-index `<is-also>` emits didn't parse, and normalising it here would be
the string surgery #109 forbids; and `InternetDraft` had no `number`, keying every
draft row to `""` in the index bsearch.

Verified against the full published corpus: **176,862 identifiers, 0 parse
failures, 0 round-trip failures**; `STD0066` → `STD 66`; draft keys are the
versionless slug, 43,564 buckets, mean 3.83, max 101, none under `""`.
`relaton.gemspec` still pins `pubid ~> 2.0.0.pre.alpha.8` and the `Gemfile`
git-pins `main`, so the IETF work depends on that pin like jcgm/bipm/etsi/cie/itu/
ieee do.

**The producer half is not sufficient on its own.** `Scraper` currently queries
with raw strings (`index.search(ref)`), and `Type#search_candidates` narrows only
for non-String queries — so switching the index to `pubid_class:` while the
consumer still passes strings makes every lookup scan the full ~177k rows *and*
render a pubid per row via `match_item`'s `item[:id].to_s.include?(id)`, which is
slower than today's plain-string index. Passing parsed `Pubid::Ietf::Identifier`
objects is part of the same change, not a follow-up — and it is also what makes
the `number` fix above matter.

`spec/ietf/relaton/ietf/pubid_contract_spec.rb` pins all of it as a standing
regression guard — every id in it is a shape pubid got wrong at least once, and
`FileIO#id_supported?` skips its round-trip check for subclassed ids, so relaton
never validates this on its own.

### The producer: `DataFetcher` writes `index-v2`

`DataFetcher` builds the index during the crawl, from the identifier it already
holds for each record — `record_index_entry` parses the primary docidentifier and
`add_or_update`s the pubid:

```ruby
Relaton::Index.find_or_create(
  :IETF, file: "#{INDEXFILE_V2}.yaml", pubid_class: ::Pubid::Ietf::Identifier
)
```

**Both halves are load-bearing.** `FileIO#save` serialises an id to its `_type:`
hash only when it is an instance of the configured `pubid_class`, so passing a
String to a `pubid_class:` index writes a v1-shaped file under a v2 name — no
error, just an index that never narrows.

Three properties worth keeping:

- **Key on the primary docidentifier**, which `serialize_and_write` already
  picks. Not the first entry: draft records carry an `I-D.foo` anchor id (not a
  pubid grammar) and their unversioned series id, which is the *primary* of a
  separate aggregator record — keying on either collides on one `id.to_s` and
  `add_or_update` silently overwrites `:file`.
- **DOIs stay out.** `10.17487/RFC3986` is not a `pubid:ietf` identifier, and one
  unparseable row invalidates the whole index. The primary is never the DOI, so
  this is already right — don't "improve" it into indexing every docidentifier.
- **Sub-series key to their own record.** `STD 66` → the STD container, not a
  constituent RFC: 42 of the 365 published sub-series include more than one, so
  there is no single document to alias to. Consumers follow `relation: includes`.

A record whose id pubid rejects is written but not indexed, warned about, and
tallied for a summary at the end of the crawl. The load is all-or-nothing —
`deserialize_id` raises on the first bad id and `load_index` then rejects the
entire index — so one malformed upstream record must cost one document, never
every lookup. All 176,862 published ids parse today; this guards against drift.

**Blast radius, worth re-checking before touching this.** The six data repos
feeding today's released consumers do *not* use this monorepo: `ietf-tools/*` pin
`relaton/relaton-ietf` @ `main` (`RelatonIetf::DataFetcher`), and
`relaton/relaton-data-{rfcs,rfcsubseries,ids}` pin it @ `lutaml-integration` —
both branches carry their own `INDEXFILE = "index-v1"` and their own fetcher. Only
`relaton/relaton-data-ietf` runs this one. So the producer flip needs no
dual-write and no cutover window.

### Still outstanding

The consumer switch, in one change: `pubid_class:` on `Scraper`'s indexes,
querying with parsed identifiers rather than strings, and collapsing the three
indexes into one. It cannot ship until an `index-v2` is published — all three type
repos still serve only `index-v1`. The data-repo side is specified in
`/work/HANDOFFS/relaton__relaton-data-ietf__unified-index-aggregator.md`.

## Testing Patterns

- **Index fixtures:** `spec/ietf/fixtures/{rfc,rss,ids}-index-v1.zip` — one per data repo — are pre-loaded into the `Relaton::Index` pool as types `:RFC`, `:RSS`, `:IDS` in `before(:suite)` (configured in `spec/ietf/support/webmock.rb`); `spec/ietf/support/vcr.rb` ignores any request whose path ends `index-v1.zip`. They are near-complete older snapshots, not curated subsets (the ids one holds 158,717 of the 166,916 published rows), so refreshing means re-copying the published `index-v1.zip` of relaton-data-rfcs/rfcsubseries/ids wholesale. There is **no** `rake spec:update_index` task in this repo.
- **VCR cassettes** in `spec/ietf/vcr_cassettes/` record HTTP interactions; tests use `vcr: "cassette_name"` metadata
- **WebMock** disables net connections by default
- **Fixtures** in `spec/ietf/fixtures/` — XML/YAML expected outputs; many tests auto-generate fixtures on first run (`File.write file, xml unless File.exist? file`)
- **Schema validation** via `ruby-jing` against the shared RNG grammars in the repo-root `grammar/` (`Jing.new "../../grammar/relaton-ietf-compile.rng"`, relative to the suite's CWD `spec/ietf/`)
- **Shared examples** for org/person parsing in `bibxml_parser_spec.rb` (`parse_org`, `parse_person`)
- **`equivalent-xml`** gem used for XML comparison (`be_equivalent_to` matcher)

## RuboCop

Inherits from `rubose/rubocop-rubose` (Ribose OSS config). Target Ruby 3.1. Rails cops disabled.
