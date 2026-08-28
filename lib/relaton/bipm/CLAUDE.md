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
now used in **one place only** — the crawler's `index-v1` generation. It was
also this flavor's consumer query parser until pubid's grammar widened enough to
replace it; see **Pubid-to-pubid lookup** below.

### Key Components

- **`Bibliography`** (`bibliography.rb`) - Main entry point. Parses the user
  reference with `::Pubid::Bipm.parse` (`#parse_ref`, returning nil on an
  unparseable ref rather than raising) and matches the pubid `index-v2` rows as
  pubid objects — see **Pubid-to-pubid lookup** below for the stem and the two
  escapes under it. The latest edition wins via
  `max_by { |r| [r[:id].year.to_i, r[:file]] }` (the file path only breaks a
  tie — Metrologia and SI Brochure rows carry no year, so all 6206 of them
  score 0 and the index sort is not stable).
- **`Id`** (`id_parser.rb`) - The flexible bespoke regex parser. Parses BIPM
  reference strings into `{group,type,number,year,…}` hashes; the `TYPES` hash
  maps full EN/FR type names to abbreviations, and `normalize_hash` applies
  `CCDS→CCTF` and leading-zero stripping. **Retained solely** as the
  `relaton-data-bipm` crawler's `index-v1` builder — it no longer parses
  queries, and it is **not** used to write this flavor's `index-v2`.
  `bibliography.rb` does not require it; `lib/relaton/bipm.rb` does, which is
  what keeps `Relaton::Bipm::Id` reachable for the crawler. JCGM is not handled
  here.
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

### Pubid-to-pubid lookup

`#get_bipm` parses the reference with `::Pubid::Bipm.parse` and matches the
index rows as pubid objects — the same shape ISO, OIML and JCGM use. The
bespoke `Id` grammar takes **no part in a query**. That became possible with
pubid `a96e9f45`, which accepts the loose consumer forms this flavor once
needed `Id` for and *normalizes* them to BIPM's canonical spelling
(`CCDS Recommendation 2 (2009)` → `CCTF Recommendation 2 (2009)`,
`CIPM 111e Réunion (2022)` → `CIPM 111<sup>e</sup> réunion (2022)`).

**The stem.** Committee-document and meeting rows are stored language- and
form-neutral, while a reference may name a language (`(2009, E)`) and always
names a form (short `CCTF REC 2` vs long `CCTF Recommendation 2`). So
`#pubid_match?` compares `exclude(:language, :form)`, adding `:year` when the
**query** carries none — `CIPM Meeting 43` has no year, its row has 1950. That
last clause is what `Id#==` did with
`other_hash.delete(:year) unless hash[:year]`; without it the lookup regresses.

**Two escapes sit under the narrowing**, each for a case where the query's
bsearch key cannot equal its row's:

1. **A bare `SI Brochure` names no edition**, so it keys to `""` while its row
   keys to `"9e"`. `#search_index` rescans the whole index. A brochure query
   with a nil edition is a *partial* reference and deliberately matches any
   brochure row — what the old `{group: "SI", type: "Brochure"}` projection
   meant. `Part N` names a section inside the brochure, not a document, so it
   stays out of the key exactly as `Id#==` kept `:part` out.
2. **`CCTF Recommendation 2009-02` parses as the literal number `2009-02`**,
   while the row keys on `2`. A rescan cannot help — no row carries that number
   — so `#year_number_retry` re-reads a trailing `YYYY-NN` as number plus year.
   It runs **only after a miss**, because `NNNN-NN` is also a real BIPM number
   (`CIPM 2005-06`), so the literal reading must win.

**One rule survives from `Id#==` and must not be dropped.** It treated a
document numbered `"1"` and a number-less one as the same document when both
carried a year, so `CIPM Resolution 1 (1879)` reached `CIPM RES (1879)`. pubid
has no such rule, and the six ordinal-less declarations
(`CGPM DECL (1889)`, `CIPM RES (1879)`, …) are the only rows it applies to — but
they are addressable *both* ways, so removing it silently broke
`CIPM Resolution 1 (1879)` and `CGPM Declaration 1 (1889)`. `#number_collapses?`
restores it by excluding `:number` from that one comparison. Both forms are in
the pinned baseline. Note the corpus has **no two rows** the rule could join
(6 number-less against 83 numbered `"1"`, no shared group/type/year), so it only
ever widens a query, never merges records.

**Cost.** `#exclude` copies the identifier, so reducing per candidate row is
expensive — roughly **165x** a plain attribute read. Two things keep the lookup
at or below what the `Id` grammar cost: the query is reduced **once per search**,
not once per row, and `#pubid_match?` rejects on `CHEAP_KEYS`
(`number group year issue article`) before reducing anything. Those are exactly
the attributes the stem never removes, so stem equality implies all of them and
the rejects cannot change an answer — a spec asserts that over the corpus rather
than trusting the argument. Without both, a bare-brochure rescan built ~7,900
copies and took **2.3 s**; with them the same lookup is 2.8 ms and a narrowed
one 0.4–0.5 ms, against 0.5–0.7 ms under `Id`.

**The regression guard.** `spec/bipm/relaton/bipm/bibliography_spec.rb` pins,
literally, the file each of the 29 references the suite exercises resolved to
under the `Id` grammar, captured before it was removed. Any change to matching
that moves a lookup fails there by name. That is the evidence for the swap —
`Id#==` was fuzzier than the stem match in ways no spec pinned (it collapsed
number `"1"` with nil, dropped `:part`/`:append`), so equivalence had to be
demonstrated rather than argued.

`Relaton::Bipm::Id` and `id_parser.rb` **stay** — `relaton-data-bipm`'s crawler
builds `index-v1` with them, and `id_parser_spec.rb` still covers them. Only
`bibliography.rb` stopped requiring the file.

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
