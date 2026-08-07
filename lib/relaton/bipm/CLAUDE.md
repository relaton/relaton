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
  `max_by { |r| r[:id].year.to_i }`.
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
