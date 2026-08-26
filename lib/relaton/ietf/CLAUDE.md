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

1. **Single document lookup**: `Processor#get` → `Bibliography.get(code)` → `Scraper.scrape_page` → parses the reference with `Pubid::Ietf` → searches the one combined `index-v2` from `relaton-data-ietf` → fetches that row's YAML

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

## Unified index (relaton#109)

Producer and consumer are both on the pubid `index-v2` now. `DataFetcher` writes
it; `Scraper` reads one combined index from `relaton-data-ietf` — replacing the
three per-type `index-v1` files (`:RFC`/`:RSS`/`:IDS`) it used to read from
`relaton-data-{rfcs,rfcsubseries,ids}`. Those three keep publishing `index-v1`
untouched, for released relatons.

`INDEXFILE` is a single constant again (`index-v2`); the `INDEXFILE_V2` that
existed while the two halves were split is gone.

Decisions taken (2026-08-18 ... 2026-08-24):

| | |
|---|---|
| Index structure | **unchanged** - `:id` + `:file` only. No `docids[]`, no summary fields; a third key invalidates the whole index for every released gem |
| `:id` shape | structured pubid hash (`Pubid::Ietf::Identifier#to_hash`) |
| Row per record | keyed by the record's **primary** docidentifier. A sub-series id resolves to its own container record, *not* to a constituent RFC - 42 of 365 sub-series include more than one RFC; consumers follow `relation: includes` |
| DOI ids | omitted - not `pubid:ietf`-representable, and one unparseable row kills the index. DOIs are served by the `doi` flavor |
| Who builds it | `DataFetcher`, during the crawl - not a separate pass over the written records, which would be a second answer to "what is this record's id" |
| Three type repos | untouched: they pin `relaton/relaton-ietf`, not this monorepo, so they keep emitting `index-v1` |

**Resolved 2026-08-26.** `relaton-data-ietf`'s RFC and sub-series records were
schema-invalid — missing `ext.doctype`, and RFC committee organizations carrying
`subdivision` with no `name` — because that repo converted the `ietf-tools`
v1.2.3 mirrors rather than crawling. It now runs `Relaton::Ietf::DataFetcher`
directly, which synthesises `doctype`, `status`, `stream`, the organization names
and the resolved WG titles. The two `pending` examples in `ietf_spec.rb` reported
`FIXED` on the first run against the new corpus and have been removed.

Two consequences of that migration to know about: record filenames are now
lowercase *and* unpadded (`data/RFC8341.yaml` -> `data/rfc8341.yaml`,
`data/STD0066.yaml` -> `data/std66.yaml`), since `output_file` derives them from
the docnumber; and the record content changed enough that the three XML fixtures
had to be regenerated.

### The consumer: `Scraper` queries with parsed identifiers

```ruby
Relaton::Index.find_or_create(
  :IETF, url: "#{IETF}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml",
         pubid_class: ::Pubid::Ietf::Identifier
)
```

`parse_id` turns the reference into a `Pubid::Ietf::Identifier` before searching,
and **that is not cosmetic**: `Type#search_candidates` narrows only for non-String
queries, so a String falls into `match_item`'s `item[:id].to_s.include?(id)`, which
renders every pubid in the index on every lookup. Measured against the live
177k-row index: **~43 s per reference with a String, sub-millisecond with a parsed
id.** A String query also returns *nothing* if `pubid_class:` is omitted, since the
rows would then be raw hashes.

`parse_id` also normalises the Internet-Draft spellings - `I-D.<slug>` and
`I-D <slug>` - onto the `draft-...` form, adding the `draft-` stem when absent
(`I-D.ietf-quic-transport`, the bibxml anchor and the `docnumber` records carry).
The old plain-string index matched that by substring; matching is exact now.
A reference pubid cannot parse returns nil, so `Bibliography.get "CN 8341"` logs
"Not found." rather than raising.

### The producer: `DataFetcher` writes `index-v2`

`DataFetcher` builds the index during the crawl, from the identifier it already
holds for each record — `record_index_entry` parses the primary docidentifier and
`add_or_update`s the pubid:

```ruby
Relaton::Index.find_or_create(
  :IETF, file: "#{INDEXFILE}.yaml", pubid_class: ::Pubid::Ietf::Identifier
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

Retiring `relaton-data-{rfcs,rfcsubseries,ids}`'s `index-v1` files, and their
`data-index/configs.yml` rows, waits until a relaton carrying this change has
shipped — see `/work/HANDOFFS/relaton__support__ietf-index-config-and-cron.md`.

## Filename collisions: workers write, the parent settles the names

`Core::DataFetcher#output_file` sanitizes `.`, `,`, `/`, `:`, `(`, `)`, `-` and
whitespace all to `-`, so two **distinct** docids can want one path. This flavor
is the only one that writes from forked processes, so it is the only one where
that could destroy a record without a word.

It did. In the first production crawl of `relaton-data-ietf`,
`data/draft-ietf-6man-hbh-processing.yaml` — the aggregator for a draft with 21
versions — was written and then overwritten by a singleton built from the
malformed sibling id `draft-ietf-6man-hbh-processing-`, which sanitizes to the
same name. The published corpus came out 177,362 index rows over 177,361 files,
and nothing in the log said so. Exactly one such group exists in that corpus;
the mechanism, not the blast radius, is the problem.

Three pieces close it, and all three are load-bearing:

1. **`@cross_process = true`, set in `fetch_ieft_internet_drafts` before the
   first `parallelize`** so the forked children inherit it. It tells
   `Core::DataFetcher#write_unique` that an existing file may belong to a peer
   and must never be overwritten.
2. **`serialize_and_write` writes through `write_unique`** and reports two extra
   keys: `docid` (the id the file was written under) and `plain_file` (the name
   it would have taken uncontested). `docid` is **not** `index_id` — `id` falls
   back through `docnumber` and `formattedref`, so on the RFC path the two
   differ (`RFC0001` vs `RFC 1`, i.e. stems `rfc0001` and `rfc-1`). Keying the
   reconciliation on `index_id` renames records to the wrong names.
3. **`reconcile_output_files`, in the parent, before `record_index_entry`.** A
   worker only learns that a path was taken, never which clashing docid deserves
   it, so left alone the winner would follow the race and the two filenames would
   swap between crawls. The parent sees every docid, so it decides: within a
   group of records that wanted one path, the alphabetically first docid keeps
   it and the rest take their digest variant.

Details of (3) that are easy to get wrong:

- It runs over **every** group, not just clashing ones. A lone record that fell
  back to a digest path must get its plain name back, or the published filename
  churns and the old file is orphaned. `next if r[:file] == target` makes that
  free for ~100% of records.
- **Losers move first.** A loser may be sitting *on* the plain path; moving the
  winner there first would destroy it.
- Two results for the **same** docid are collapsed, not split: the stray file is
  deleted and one warning is emitted, which is what the crawl did before. The
  stray may already be **gone** — the fallback name is keyed on the docid, so two
  workers that both lost the race to the plain path land on one name and the
  first of them renames it onto the target. The result must follow the document
  to the target anyway, or the index gets a row pointing at nothing.
- Sorting *unique docids* leaves no tie for Ruby's unstable `sort_by` to resolve
  differently between runs.
- A failed rename warns and carries on. A multi-hour crawl must not die at the
  last step.

`report_collisions` restates the total once at the end of the crawl, beside
`report_unparsed` and `report_unindexed` — one line for a crawl that writes
~177k records.

The sequential paths (`fetch_ieft_rfcsubseries`, `fetch_ieft_rfcs`) get no
reconciliation pass and need none: one process, so `unique_output_file` is
already deterministic there. They do now emit a digest filename for a genuine
cross-docid collision instead of overwriting, which follows `rfc-index`
iteration order — stable for a given input.

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

- **Index fixture:** `spec/ietf/fixtures/ietf-index-v2.zip` - the combined index, copied **wholesale** from `relaton-data-ietf` rather than curated, since a subset goes stale and surfaces as a 404 on the document fetch. `spec/ietf/support/webmock.rb` deserialises it into pubid ids, sorts by the narrowing key, sets `sorted = true` (without which every lookup is a ~40 s scan) and pre-loads it into the pool as `:IETF` in `before(:suite)`; `spec/ietf/support/vcr.rb` ignores requests ending `index-v2.zip`. Refresh by re-downloading that zip. There is **no** `rake spec:update_index` task in this repo.
- **VCR cassettes** in `spec/ietf/vcr_cassettes/` record HTTP interactions; tests use `vcr: "cassette_name"` metadata
- **WebMock** disables net connections by default
- **Fixtures** in `spec/ietf/fixtures/` — XML/YAML expected outputs; many tests auto-generate fixtures on first run (`File.write file, xml unless File.exist? file`)
- **Schema validation** via `ruby-jing` against the shared RNG grammars in the repo-root `grammar/` (`Jing.new "../../grammar/relaton-ietf-compile.rng"`, relative to the suite's CWD `spec/ietf/`)
- **Shared examples** for org/person parsing in `bibxml_parser_spec.rb` (`parse_org`, `parse_person`)
- **`equivalent-xml`** gem used for XML comparison (`be_equivalent_to` matcher)

## RuboCop

Inherits from `rubose/rubocop-rubose` (Ribose OSS config). Target Ruby 3.1. Rails cops disabled.
