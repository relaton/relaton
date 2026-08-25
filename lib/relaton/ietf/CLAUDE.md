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

## Thin records inherit from their constituents

Two builders produce records for documents that have **no upstream source of
their own**, and both would otherwise publish without date, doctype or source:

| Builder | File | Inherits from |
|---|---|---|
| `to_subseries_item` | `rfc/entry.rb` | the newest RFC in its `is-also` |
| `build_unversioned_doc` | `data_fetcher.rb` | the newest version in `sorted` |

This is **not** a parsing gap to go fix in the XML mapping. A sub-series entry in
`rfc-index.xml` is only a pointer:

```xml
<bcp-entry>
  <doc-id>BCP0003</doc-id>
  <is-also><doc-id>RFC1915</doc-id></is-also>
</bcp-entry>
```

The RFC Editor publishes no date, title, author or status for it, because a
sub-series *has* no metadata of its own — it is a label on one or more RFCs.
Unversioned draft aggregators are further still from an upstream document: they
are synthesised from the versions found on disk.

Neither site needs a second pass or another read of the corpus — `rfc_index` and
`sorted` already hold the constituents at build time. (A downstream
implementation in `relaton-data-ietf`'s crawler did use a second pass over
written files, because its groups could span source repos; that constraint does
not exist here.)

**Constituent lookup is normalised on both sides, deliberately.**
`Entry.squish` folds case and strips whitespace and dots. Relation targets and the
docids they reference disagree in the published corpus (`dyndNS` vs `dyndns`),
which left 28 documents undated downstream on a strict lookup — and, in
`build_relations`, silently downgraded a full constituent bibitem to a minimal
one.

`rfc_index` is therefore **keyed by `Entry.squish(doc_id)`, and the caller builds
it** — `fetch_ieft_rfcsubseries` does so once for the crawl. Normalising inside
`Entry` instead would rebuild a ~9,800-row table for each of the 367 sub-series
(measured: ~161 MB retained, ~6 s), all of it the same table.

Why it matters beyond tidiness: the Pages index sorts by date, so undated records
sort as one undifferentiated block, and a record with no `ext.doctype` renders
with no document type at all.

Inherited values are `dup`'d rather than shared with the constituent's own bib —
aliasing them would make a later edit to the aggregator mutate the `-NN` record.

Verified against the live `rfc-index.xml`: **367/367 sub-series dated**, 367/367
with full constituent bibitems, in 1.4 s; `BCP 3` → 1996-02, `STD 51` → 1994-07,
`STD 66` → 2005-01 (RFC 3986's date).

## bibxml encoding: transcode, don't scrub, don't skip

Some bibxml files declare `encoding='UTF-8'` and carry **Windows-1252** bytes —
smart quotes and accented Latin letters. `File.read(encoding: "UTF-8")` only
*tags* a string; it validates nothing, so those reached lutaml as invalid UTF-8
and `Rfcxml::V3::Reference.from_xml` raised `Lutaml::Model::InvalidFormatError`.

`read_bibxml` transcodes them (`data_fetcher.rb`). Three things make that the
right call rather than `scrub`:

- **All of them decode losslessly as CP1252** — 125 of the ~122k published files
  are affected, 0 unmappable.
- **The bytes present prove CP1252, not Latin-1.** `0x91`–`0x94` (`‘ ’ “ ”`) are
  control characters in Latin-1.
- **`scrub` is lossy.** It replaces each byte with `U+FFFD`: `client’s` becomes
  `client�s`, `Muñoz` becomes `Mu�oz`. Author surnames are among the
  affected fields. Verified on a real file — scrub and transcode yield the same
  *length*, so a length check will not catch the damage.

Don't copy `lib/relaton/bipm/si_brochure_parser.rb:33-35`, whose
`force_encoding` guard is a no-op. The `scrub` idiom at
`lib/relaton/itu/data_crawler_r.rb:588-599` is right *there* because it repairs
scraped HTML with no recoverable original; here there is one.

### Why the rescue is per file, and why the tally is in the parent

`parse_bibxml` rescues `StandardError` — not a narrow list. lutaml raises
`InvalidFormatError` on bad bytes, but the converter also runs regexes over
parsed text (`parse_surname_initials` and friends), which raise
`ArgumentError: invalid byte sequence` on anything that slips through.

It has to be **inside** the worker. The drafts path runs under `Parallel.map`,
which discards every result from the pass when a worker raises — so one bad file
out of ~167k meant no index at all, plus the already-written records orphaned on
disk, because `record_index_entry` and `index.save` only run after both passes
return. A rescue around `parallelize` would salvage "the crawl didn't die", not
"the other 166,999 files got indexed".

The skip therefore rides back as `{ unparsed: path, error: }` and is counted in
the parent, the way `parse_pubid`'s result rides back as `result[:pubid]` — a
counter incremented in a worker process is lost. `report_unparsed` warns once
with a count and a sample, not once per file.

A failed version is dropped from `sorted` **before** `link_neighbor_relations`
and `build_unversioned_doc` run, since both dereference `entry[:bib]`. Knock-on
to accept: neighbours then link across the gap, and if the dropped file was the
newest, the aggregator inherits from the previous version. With CP1252 recovery
that should approach zero — which is the argument for recovering over skipping.

Verified end to end on 41,408 real draft files (16 invalid UTF-8): the crawl
completes in 57 s, writes 46,461 records and 46,461 index rows, **0 skipped**,
and the affected files come through with their real characters —
`\x93Access Node Contr` → `“Access Node Contr`.

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
