# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-bipm is a Ruby gem that retrieves BIPM (Bureau International des Poids et Mesures) standards metadata for bibliographic use. It's part of the larger Relaton family of gems that handle bibliographic data for standards organizations.

## Common Commands

- **Install dependencies:** `bundle install`
- **Run all tests:** `bundle exec rake spec`
- **Run a single test file:** `bundle exec rspec spec/relaton/bipm/bibliography_spec.rb`
- **Run a single test by line:** `bundle exec rspec spec/relaton/bipm/bibliography_spec.rb:42`
- **Interactive console:** `bin/console`

## Architecture

### Namespace & Module Structure

All code lives under `Relaton::Bipm` (in `lib/relaton/bipm/`). The gem name is `relaton-bipm`, the require path is `relaton/bipm`.

### Pubid-backed `index-v2` (the runtime index)

The flavor's runtime index is the **pubid-backed `index-v2`** (`INDEXFILE =
"index-v2"`), whose rows are `Pubid::Bipm` identifiers serialized as
`_type: pubid:bipm:{committee-document,meeting,metrologia-article,si-brochure}`
— mirroring the JCGM/OIML/JIS convention, not BIPM's old bespoke
`{group,type,number,year}` hash. The `DataFetcher` builds it (`pubid_class:
::Pubid::Bipm::Identifier`), and the consumer reads it.

The **legacy bespoke `index-v1`** (the old `{group,type,number,year}` hash form)
is no longer produced or read by this flavor. It is still published by
`relaton-data-bipm`'s own `crawler.rb`, which builds it with the **retained**
`Relaton::Bipm::Id` (this flavor keeps `Id` public for exactly that). So `Id` is
now used in two places only: the crawler's `index-v1` generation, and this
flavor's **consumer query parsing** (below).

### Key Components

- **`Bibliography`** (`bibliography.rb`) - Main entry point. Parses the user
  reference with the flexible bespoke `Id` grammar (`parse_ref`, returning nil on
  an unparseable ref rather than raising), then looks it up in the pubid
  `index-v2`. Because the stricter `Pubid::Bipm` grammar rejects the loose
  consumer forms users type (`CCTF Meeting 14 (1999)`, `CCDS …`, `… (2009, EN)`,
  `SI Brochure Part 1`, French `Décision`/`Réunion`), matching stays on `Id`:
  each index row's `Pubid::Bipm` object is projected back to the bespoke
  `{group,type,number,year,lang}` hash by `#id_hash` and compared with `Id#==`
  (its number/year/lang collapsing preserved); the latest edition wins via
  `max_by { |r| [r[:id].year.to_i, r[:file]] }` (the file path only breaks a
  tie — Metrologia and SI Brochure rows carry no year, so all 6206 of them
  score 0 and the index sort is not stable).
- **`Id`** (`id_parser.rb`) - The flexible bespoke regex parser. Parses BIPM
  reference strings into `{group,type,number,year,…}` hashes; the `TYPES` hash
  maps full EN/FR type names to abbreviations, and `normalize_hash` applies
  `CCDS→CCTF` and leading-zero stripping. **Retained** as the query parser
  (above) and as the `relaton-data-bipm` crawler's `index-v1` builder; **not**
  used to write this flavor's `index-v2`. JCGM is not handled here.
- **`Processor`** (`processor.rb`) - Relaton framework integration point (extends
  `Relaton::Core::Processor`). Registers prefix `BIPM` and default prefix pattern
  matching BIPM, CCTF, CCDS, CGPM, CIPM, JCRB (JCGM was split out into the `jcgm`
  flavor). `remove_index_file` targets `index-v2`.
- **`DataFetcher`** (`data_fetcher.rb`) - Bulk fetches from three data sources:
  `bipm-data-outcomes`, `bipm-si-brochure`, `rawdata-bipm-metrologia`. Delegates
  to specialized parsers, which route every index write through the public,
  **guarded** `#add_to_index(docnumber, path)` — it parses `docnumber` with
  `::Pubid::Bipm.parse` and stores the identifier object, or **warns and skips**
  an unparseable id rather than aborting the crawl (mirrors
  `Relaton::Jcgm::DataFetcher#add_to_index`; `Relaton::Index` rejects a whole
  index if one row fails to deserialize). Public so `relaton-data-bipm`'s crawler
  can index its curated `static/` docs through the same guarded path.
- **`Item`** / **`ItemData`** (`model/item.rb`, `item_data.rb`) - The
  bibliographic item model, extending `Relaton::Bib::Item`. Supports XML, YAML,
  and JSON serialization.
- **`model/`** directory - Lutaml model classes (Bibdata, Bibitem, Ext, etc.) for
  XML/YAML serialization.

### Index narrowing, and why it needs a fallback

`Relaton::Index::Type#search` binary-searches the index only when the caller
gives it an identifier; a block-only call scans all ~7,900 rows. `#search_index`
therefore parses the reference a **second** time, with pubid (`#narrowing_id`),
purely to supply that key — the same `index.search(pubid) { … }` call shape ISO,
OIML and JCGM use. The *match* stays on `Id#==`, because pubid cannot parse the
loose forms. Measured on the spec fixture: **19–28x** faster, for every query
form the suite exercises.

Two cases make an **empty narrowed range** possible even though the document is
in the index, so `#search_index` repeats the search over the whole index when
the narrowed one comes back empty:

1. **The two grammars disagree on the number.** `CCTF Recommendation 2009-02`
   is year 2009 / number 2 to `Id`, and the literal number `2009-02` to pubid,
   while the row keys on `2`. The reading is genuinely ambiguous — `NNNN-NN` is
   a real BIPM number form elsewhere (`CIPM 2005-06`) — so this is not an
   upstream bug to fix.
2. **The index was built by a pubid that derived no `number`.** No longer the
   case — `relaton-data-bipm` republished `index-v2` on 2026-08-24 and 7915 of
   its 7922 rows now carry one, leaving 7 in the `""` bucket (the six
   ordinal-less declarations and `data/metrologia.yaml`). It was the case
   before, when 6206 metrologia and si-brochure rows all keyed to `""`, and it
   becomes the case again for anyone holding an older index — which is why the
   fallback stays.

The fallback costs one extra binary search and makes the narrowing **incapable
of regressing a lookup** — worst case it is exactly the full scan this method
did before. `spec/bipm/relaton/bipm/bibliography_spec.rb` covers all three paths
(narrowed, fallback and pubid-rejected), distinguishing them by how many times
`#search` is called rather than by the scanned-row count — an empty bucket
contributes no scanned rows, so a fallback lookup scans exactly as many rows as
an unnarrowed one.

One hazard needs more than the empty-check to rule out: the fallback fires only
on an **empty** narrowed range, so a query whose matches straddle two buckets
would lose one silently. `Id#==` collapses number `"1"` and no number, and that
is the same field the index buckets on. The specs settle this by assertion, not
by argument — `#search_index` must return the same rows as the unconditional
full scan, checked over every row that can straddle the `"1"`/`""` boundary and
over a sample drawn across the index. They also re-parse all 1,706 numbered
rows to guard the key derivation against drift.

`#narrowing_id` used to return nil for ~8 loose forms pubid rejected, so those
scanned the whole index. **That gap is closed.** pubid `a96e9f45` accepts the
meeting word order, the French type names, the `CCDS` alias, two-letter
language codes and the SI Brochure `Part`/`Appendix` suffix, so over every form
the suite exercises pubid now parses everything `Id` parses — it refuses only
input `Id` refuses too, and `get_bipm` returns before reaching it. The nil
branch is therefore unreachable in practice; it is kept because nothing
guarantees the two grammars stay converged, and
`spec/bipm/relaton/bipm/bibliography_spec.rb` drives it by withholding the key
rather than by naming a reference.

That convergence unlocks the real simplification, which is **not yet done**:
`get_bipm` can now match pubid to pubid like ISO does
(`index.search(pubid) { |r| pubid_match? r[:id], pubid }`), retiring `Id`,
`#id_hash`, `#parse_ref` and the fallback from the query path. `Id` itself must
stay public — `relaton-data-bipm`'s crawler still builds `index-v1` with it.
Doing so would also end the `CCTF Recommendation 2009-02` disagreement, since
one grammar cannot disagree with itself.

### Data Sources

The gem fetches from three external datasets:

1. **bipm-data-outcomes** - CGPM/CIPM/committee resolutions, recommendations, decisions (the `jcgm` meeting dir is now harvested by the `Relaton::Jcgm::DataFetcher` instead)
2. **bipm-si-brochure** - SI Brochure documents
3. **rawdata-bipm-metrologia** - Metrologia journal articles (parsed from CrossRef-style data)

### Testing

- **Index fixture:** `spec/bipm/fixtures/index-v2.zip` (the pubid `index-v2`) is
  deserialized via `Pubid::Bipm::Identifier` and pre-loaded into the
  `Relaton::Index` pool in `before(:suite)` (`spec/bipm/support/webmock.rb`,
  mirroring the JCGM/JIS setup). It was regenerated from the real
  `relaton-data-bipm` docs' docnumbers (each parsed with `Pubid::Bipm`); the
  handful that pubid can't parse — JCGM orphans, `CIPM 2005-06`, docs removed
  upstream — are absent by design.
- **Parser specs** assert the parsers call `data_fetcher.add_to_index(docnumber,
  path)` with the right docnumber string (the pubid parsing/guarding lives on the
  mocked `DataFetcher`, keeping the parser tests format-agnostic).
- Tests use RSpec with VCR cassettes (`spec/bipm/vcr_cassettes/`) and WebMock.

### Dependencies

Key runtime dependencies: `pubid` (provides `Pubid::Bipm`), `relaton-bib` (core
bibliographic model), `relaton-index` (index management), `relaton-core`
(framework base), `parslet`, `mechanize` (HTTP), `faraday`, `rubyzip`.
