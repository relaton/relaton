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

**Known blocker, do not lose.** `relaton-data-ietf`'s **RFC and sub-series records
are schema-invalid**: every one sampled lacks `ext.doctype`, and RFC committee
organizations carry `subdivision` with no `name`. Drafts are clean. So the repoint
is correct but should not ship until the data is fixed - see
`/work/HANDOFFS/relaton__relaton-data-ietf__records-fail-ietf-grammar.md`. Two
examples in `ietf_spec.rb` are `pending` on it and will turn red when it is fixed.

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

The repoint is written but **must not ship** until `relaton-data-ietf`'s RFC and
sub-series records validate (see the blocker above). Once they do, the two
`pending` examples in `ietf_spec.rb` turn red; regenerate
`spec/ietf/fixtures/{bib_item,bcp_47}.xml` and drop the `pending` lines.

Retiring `relaton-data-{rfcs,rfcsubseries,ids}`'s `index-v1` files, and their
`data-index/configs.yml` rows, waits until a relaton carrying this change has
shipped — see `/work/HANDOFFS/relaton__support__ietf-index-config-and-cron.md`.

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
