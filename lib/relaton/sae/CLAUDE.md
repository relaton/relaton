# CLAUDE.md — SAE flavor

`Relaton::Sae` fetches SAE International standards (relaton/relaton-sae#1).

## Development

- `bundle exec rake spec:sae` — this flavor's suite (from the repo root).
- No VCR: the specs stub HTTP with WebMock. `spec/sae/fixtures/crossref/`
  holds three Crossref cursor pages built from real records (11 works:
  six J3016/J3194 editions, three AMS4121 revisions, a part and a
  letter-pair number). `spec/sae/fixtures/index-v2.yaml` and `fixtures/data/` are the
  **output of `DataFetcher` over those pages**: regenerate both together by
  running the crawler over the page fixtures, never by hand.

## Where the data comes from

**sae.org answers every script request with a CAPTCHA** (product pages and
search alike), so no scraper is possible. SAE deposits every standard edition
with Crossref instead: prefix `10.4271`, type `standard`, ~47,700 records. The
DOI suffix is SAE's own edition code in lowercase:

| DOI | SAE code | scheme |
|---|---|---|
| `10.4271/j3016_202104` | `SAE J3016_202104` | J-series: `_YYYYMM` edition date |
| `10.4271/ams4121j` | `SAE AMS4121J` | aerospace: revision letter, no date |
| `10.4271/j2337/2_201702` | `SAE J2337/2_201702` | a part |

Crossref's text search does **not** find a standard by its id (it matches
titles), so an undated reference cannot be answered live. The flavor is
therefore index-based, the ECMA/IALA shape:

- **Producer** — `DataFetcher` (`relaton fetch-data sae-crossref`) walks
  `api.crossref.org/prefixes/10.4271/works?filter=type:standard` with the
  deep-paging cursor (1000 a request, one request a second through
  `Core::Pacer`; 429/5xx and transport errors retried with back-off, five
  attempts, then `RequestError`, because
  a partial crawl would publish a partial index). Each work goes through
  `Relaton::Doi::Parser`, then gets SAE's code as its **primary**
  docidentifier (type `SAE`), the DOI beside it, and `ext` doctype
  `standard`, flavor `sae`.
- **Consumer** — `Bibliography.get` reads the `relaton-data-sae` Pages index
  (`PAGES_URL`) and the document from `ENDPOINT` (raw GitHub).

## Three identifier forms

`DoiCode` gives each record three strings:

- `#native` — the code in the DOI's spelling, `SAE J3016_202104`,
  `SAE AMSQQA250/4B`. The output file is named after it
  (`data/sae-amsqqa250-4b.yaml`), so a file name never depends on pubid.
- `#printed` — the code as SAE prints it (`SAE AMS-QQ-A-250/4B`): pubid's
  render of the native code, or the native code when pubid cannot read it.
  It is the primary docidentifier.
- `#reference` — what the index row is parsed from: the native code when the
  DOI has a date, else the code with the year of the record's `approved` date
  (`SAE AMS4121J:2017`), so a dated reference also reaches an aerospace
  revision.

`Pubid::Sae` (pubid >= 2.0.9, pubid#665) reads all three, the month
included, so the `Db` keys the query and the fetched document with the
default `cache_pubid`. A reference pubid cannot read (`SAE J3016_2021`,
`SAE CPGM2016`) answers nil with a log line (relaton#235); it does not raise.

## Selection

`index.search(pubid)` with no block, so the subset match `query === row`:
a revision, a year or a month the query omits matches any value; the type
(`J`, `AMS`, …) is compared, and a part and an amendment are `subset_strict`
(`SAE J2337` does not answer with `SAE J2337/2`). Of the matches the highest
revision wins (`[length, letters]`, so `AA` follows `Z`), then the latest
year and month, then the file name (the index sort is not stable). A year
argument goes on a **copy** of a pubid handed in by `Db`.

The index key carries the month, so two editions of one year are two rows.
Two DOIs that spell one code (`ams-4121j`, `ams4121j`) share a key, and
`DataFetcher#add_to_index` keeps the later one (DOI date, then approval
date).

## What pubid still cannot read

About 960 of the ~47,700 deposits: 791 `CP*` collected-paper products (not
standards) and ~170 one-off shapes (`SUP1` supplements, language tails such
as `_PTBR`, `_4Q2012`, `_MMYYYY` dates). See pubid's `lib/pubid/sae/CLAUDE.md`.
Such a record is written, reported in `@errors` (the crawl's GitHub issue),
and not indexed: one row that fails to deserialize makes `Relaton::Index`
reject the whole index.

A multi-letter tail stays in `number` (`J1939DA`, and also `AMS4121AA`), so
a two-letter revision is its own bucket: `SAE AMS4121` does not reach it.
