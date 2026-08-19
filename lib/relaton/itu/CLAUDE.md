# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

The ITU (International Telecommunication Union) flavor of the combined `relaton`
gem — retrieval and modelling of ITU-T and ITU-R bibliographic metadata. All of it
lives under `Relaton::Itu` in `lib/relaton/itu/`; the old flat `RelatonItu`
namespace is gone.

## Commands

```bash
cd spec/itu && bundle exec rspec -I . .          # the flavor's suite (run from its own dir)
bundle exec rake spec:itu                        # the same, from the repo root
cd spec/itu && bundle exec rspec -I . relaton/itu/item_spec.rb     # one file
```

## Architecture

### Model Layer (Lutaml::Model)

All model classes use `Lutaml::Model::Serializable` for XML/YAML serialization:

- **`Item`** → extends `Bib::Item` (main bibliographic item)
- **`ItemData`** → extends `Bib::ItemData` (used by DataParserR for parsed documents)
- **`Bibitem`** / **`Bibdata`** → extend `Item`, mix in shared behavior from `Bib`
- **`Ext`** → extends `Bib::Ext` with ITU-specific fields (doctype, structuredidentifier, question, recommendationstatus, ip_notice_received, meeting, meeting_place, meeting_date, intended_type, source)
- **`Doctype`**, **`StructuredIdentifier`**, **`EditorialGroup`**, **`Bureau`**, **`Group`**, **`ApprovalStage`**, **`RecommendationStatus`**, **`Question`**, **`Meeting`**, **`MeetingDate`** — ITU-specific metadata types

### Runtime lookup (`HitCollection#search`)

ITU removed the `net4/.../GlobalSearch/RunSearch` endpoint (F5 WAF, HTTP 500) that
used to *discover* every reference. Discovery now has three routes, matched in this
order (an Operational Bulletin reference matches both `^ITU-T` and `OB.`, so the
publication arm must come first):

| reference | route | source |
|---|---|---|
| `ITU-R RR …`, `… OB.N …` | `#request_publication` | live `www.itu.int/pub/{R-REG-RR-YYYY \| T-SP-OB.N-YYYY}` |
| `ITU-T …` | `#request_recommendation` | combined `index-v2`, live fallback |
| `ITU-R …` | `#request_document` | combined `index-v2` |

- **Publications** (Radio Regulations, Operational Bulletins) are **not** in the
  dataset, but their landing-page id is derivable from the reference, so no search
  is needed. No `ref.year` → no hit; a `notfound` redirect or 404 → no hit. The page
  is parsed by `RadioRegulationsParser` as before (its `#doc_url` `dest=` unwrap is
  a no-op for these direct URLs, kept for the legacy shape).
- **Recommendations** prefer the index (offline, every edition, no scraping) and
  fall back to the live `rec.aspx?rec={code}` → `11.1002/1000/{idrec}` →
  `getRecEditions` pair, which is the discovery half of relaton-itu#89. The
  fallback is a **narrowing** safety net. It used to be load-bearing for 706
  ITU-T records whose ids `Pubid::Itu` could not parse; pubid #325 parses every
  one of them, so after the next crawl **no ITU-T record is unindexed for that
  reason** (see **Index/data gap** below). What still needs it: Implementers'
  Guides (`ITU-T G.Imp712`) aren't harvested at all, and newly approved editions
  appear on `rec.aspx` before the next crawl. It triggers when the index has **no** row *or*
  when the reference names a year no indexed edition has (a heuristic — a hit that
  `Bibliography#search_filter` later discards still counts as satisfying); if the
  live path then finds nothing, the indexed editions are kept so the "no match for
  `<year>` year, though there were matches found for …" hint survives.
  **Known gaps:** a `(V##)` reference resolves live (`getRecEditions` returns the
  versioned `rec_name`) and will resolve from the index after the next crawl; an
  `Annex` reference resolves through **neither** route until then — the published
  index has no annex rows and `getRecEditions` returns no `Annex` entries. Undated
  `ITU-R RR` / `OB.` references are also unresolvable: the `/pub` id needs a year
  and there is no enumeration source left to find the latest.
- **Index hits are lazy.** `#index_hits` builds one `Hit` per matching row carrying
  `code:` (`row[:id].to_s` — the same dated docidentifier the data record holds),
  `url:` and `file:`; `Hit#item` branches on `:file` and calls
  `HitCollection#fetch_item` only for the edition `Bibliography` actually selects.
  Because the hit's `code` is the dated docid, `Bibliography#search_filter` /
  `#isobib_results_filter` year selection needed no change. Hits are sorted
  newest-first (`#edition_key`, the **first** date in the code, so an amendment
  sorts by the year of the recommendation it amends) because
  `isobib_results_filter` takes the first hit for a year-less reference.
- Live recommendation hits deliberately carry **no `:ref` key** — that drives
  `Hit#gi_imp`, which would route an Implementers' Guide onto the `getImplGuides`
  endpoints; the live `G.Imp712` record is built from `getRecHdrDetail` like any
  other. (`gi_imp` has been inert since the RunSearch hits never set `:ref`.)
- **Metadata parity:** an indexed Recommendation is only as rich as the published
  data record. `relaton-data-itu` was re-crawled with the enriched `DataParserT`
  (below) on 2026-08-12, so an indexed record now carries the same abstract, ISO
  co-identifier, contributors, status, edition and relations a live-fallback
  record does — `itu_t_y_3500` and `itu_t_a_13` assert exactly that. A crawl
  predating the enrichment would silently reintroduce the asymmetry, so the data
  repo's own suite guards against republishing thin records.

### Data Fetching

- **`DataFetcher`** extends `Core::DataFetcher`. `#fetch(source)` routes on the
  dataset name (from `Processor#@datasets = %w[itu-r itu-t]`): `"itu-t"` →
  `#fetch_recommendations`, anything else (`"itu-r"`, `nil`) →
  `#fetch_publications`, then `index.save` + `report_errors` for either.
- **ITU-R harvester** (`#fetch_publications`) — restored on the crawl that
  replaced the decommissioned RunSearch enumeration (issue #75). It walks
  `DataCrawlerR::FAMILIES` series by series, so a series ITU throttles costs
  that series rather than the run. `RELATON_ITU_DELAY` (default 1 s) tunes
  politeness; `RELATON_ITU_MODE` picks the mode, so two scheduled jobs differ
  by environment rather than by code:

  | mode | cost | what it is for |
  |---|---|---|
  | `:full` (default) | ~7k requests, ~4 h | the weekly rebuild: wipe `data/itu-r-*` first and let ITU be the sole author of the result |
  | `:top_up` | enumeration + one request per **new** edition | the daily job: same document walk, but `#held?` answers from the level-2 row whether the dataset already has an edition, so the expensive per-edition page is never fetched for one we hold |

  **A top-up refuses to run before the first full rebuild** (`#legacy_reports`).
  Until then the published Reports still carry their pre-#110 bare docids, and
  topping up would add a second copy of each under its `Report …` name. One
  wipe-and-rebuild retires those names for good — which is why the harvester
  needs no migration step: the rebuild *is* the migration.

**Measured** on the BO slice of R-REC + R-REP, back to back (2026-08-19): a
full rebuild is **221 requests / 548 s** for 127 records; the top-up
immediately after is **94 requests / 268 s** and adds nothing — it saves
exactly the 127 per-edition pages, 57% of the requests. Corpus-wide that
scales to roughly **7k requests (~4 h) full** against **~2.5k (~1.4 h)
top-up**: cheaper, but not cheap — the enumeration still costs one request per
document, because a new edition cannot be noticed without reading the document
page. (`/rec/new.asp?lang=en`, linked from every series page, may be a real
delta feed; unexplored.) Earlier corpus figures still hold: ~2.1 s per request
at the 1 s delay, and 0 dates rewritten / 0 records lost across 3,600 merged
records.

  Pair the modes with the data repo's existing collapse guard
  (`guard_itut_harvest`, which aborts a publish whose file count halves) — a
  wipe makes that guard the only thing between a throttled crawl and a
  published hole, and ITU-R wants its own, per family.
- **`#index_files(glob)`** indexes records already on disk through the same pubid
  guard and unparseable-id reporting as the harvests. It is what
  `relaton-data-itu`'s crawler used while ITU-R had no harvester; a run that now
  calls `#fetch "itu-r"` gets that indexing as a side effect of the merge.
- **ITU-R crawler (`DataCrawlerR`, issue #75)** — ITU-R
  metadata is still fully server-rendered, so enumeration *is* possible without
  RunSearch; `data_crawler_r.rb` proves it. Three levels, per family (`FAMILIES`):

| family | index | grouping level | page URL | date |
|---|---|---|---|---|
| `R-REC` Recommendations | `/pub/R-REC/en` | 16 series letters | `/rec/<id>/en` | `Approved in …` — **approval** |
| `R-REP` Reports | `/pub/R-REP/en` | 14 series letters | `/pub/<id>/en` | files' "Posted" — **publication** |
| `R-QUE` Questions | `/pub/R-QUE/en` | 6 study groups (`SG01`…) | `/pub/<id>/en` | files' "Posted" |
| `R-RES` Resolutions | `/pub/R-RES/en` | **none — flat** | `/pub/<id>/en` | files' "Posted" |

  e.g. `/rec/R-REC-BO/en` (54 documents) → `/rec/R-REC-BO.1130/en` (Main +
  Previous versions, one row per edition) → `/rec/R-REC-BO.1130-5-202602-I/en`.
  Every id names its own family (`#family_of`), so the level-2/3 methods take an
  id alone. That date column is the whole reason `DataMergeR` exists (below):
  a harvested **report** reproduces the published `date:` exactly (verified for
  `ITU-R BO.1227-2` → `1998-01`), a harvested **recommendation** cannot.
  Load-bearing details:
  - URLs are **rebuilt** from each link's `parent=` id (`/rec/<id>/en` for a
    recommendation, `/pub/<id>/en` for a report); the pages' own
    `./recommendation.asp?…` / `publications.aspx?…` hrefs resolve against the
    series directory and do **not** reach the canonical page.
  - The PDF link is matched **anchored on the edition id**
    (`//a[contains(@href,'<id>') and contains(@href,'PDF-E')]`): every `/pub`
    page carries a QUICK LINKS sidebar whose Publication Catalogue entry is
    itself a `…-PDF-E.pdf`, so an unanchored match would give a report edition
    with no English PDF the catalogue's URL — which `DataMergeR` would then
    backfill into the dataset permanently.
- **Each family spells its identifier differently**, and the published dataset
  is the authority (`DataParserR#family_docid`). `R-REC` uses the displayed
  code; `R-REP` prefixes it (`Report ITU-R BT.2020-1`, see the collisions note);
  `R-QUE` appends a colon (`202-2/1` → `ITU-R 202-2/1:`); and `R-RES` cannot use
  its code at all — the page renders `Res.1-9 (2023)` while the record is
  `ITU-R R.1-9`, which only the **page id** (`R-RES-R.1-9-2023`) carries. All
  four reproduce the published filenames exactly, verified live.
- **`R-HDB` is deliberately not implemented.** Its pages expose several editions
  per handbook, but the published dataset carries **one record per handbook
  number** (`ITU-R 01.HDB`; 60 records, 60 distinct docids, no edition in the
  id), so harvesting every edition would collapse them onto one filename and
  the merge would report collisions instead of records. Implementing it needs a
  decision first: harvest only the current edition, or change the identifier
  convention for 60 published records. `#config` raises meanwhile.
  - The docid comes from the **displayed code** minus ` (MM/YYYY)` — `BO.1212
    (10/95)` → `ITU-R BO.1212`, *not* the page id's `ITU-R BO.1212-0`. That
    reproduces the published filenames and index rows exactly (the spec asserts
    `data/itu-r-bo-1130-5.yaml` / `data/itu-r-bo-1212.yaml`).
  - The date comes from the id (a recommendation id ends in `YYYYMM`, a report id
    in its year; displayed codes use 2-digit years pre-2000, so the id is the only
    unambiguous source), upgraded by the level-3 page. **For recommendations that
    is the approval date, and the preserved records carry RunSearch's publication
    date.** Measured across the whole BO series: the date differs for **82/82**
    records and the *year* differs for **48** of them (`ITU-R BO.600-1`: published
    `2002-01` vs approved `1986-07`). Since references are matched by year, that
    is a regression, not a precision upgrade — hence `DataMergeR`.
  - `deep: false` costs `1 + documents` requests (~1.3k for all 16 REC series)
    with coarser dates and a pattern-derived PDF URL; `deep: true` adds one
    request per edition. **Measured live on BO (2026-08-13):** 54 documents,
    82 editions, 137 requests in 121 s at a 0.4 s delay, no throttling — so the
    whole ~5.3k-record corpus is roughly 7k requests / ~1 h, inside the 6 h
    Actions cap. Coverage on that run: 82 harvested vs 83 published BO
    recommendations (the one gap is `ITU-R BO.4/BL/4`, a BL-form id absent from
    the series page); the other 23 published `itu-r-bo-*` files are reports.
  - **In deep mode the edition page is the authority.** An edition with no
    `!!PDF-E.pdf` (older ones are Word-only, e.g. `R-REC-BO.1130-0-199408-S`) is
    left **sourceless** rather than given a derived URL that 404s, and a page
    that returns no approval date — ITU served an empty 200 for
    `R-REC-BO.1130-4-200104-S` while the cassette was being recorded — is
    **warned about** before falling back to the id's date, so a degraded deep
    crawl can't pass for a clean one. Every level also warns when it finds
    nothing (a layout change would otherwise read as an empty corpus).
  - **Throttling has two shapes, and one is silent.** Measured over a full
    corpus run: `/rec` answers **HTTP 503**, `/pub` answers **302 →
    `/en/publications/pages/notfound.aspx`** — indistinguishable from "no such
    document" unless you look, and it once emptied all 14 report series while
    every level dutifully reported success. `#get` therefore retries both
    (`RETRIES` = 3, linear `RETRY_BACKOFF`) and raises when they persist, so a
    throttled series fails loudly; `#warn_if_empty` is the backstop that caught
    it in the first place. A ~1 s delay ran 13 of 14 report series clean where
    0.4 s did not.
  - **Two row/link shapes that look like data and are not.** ITU lists some
    editions **twice**: a `…-I` row coded `M.2083-0` and a `…-P` row whose
    displayed Number is the associated *Question* (`M.5/BL/22`) — so `#editions`
    keeps only rows whose code starts with the document's own number, or the
    crawl mints Recommendations out of question numbers. And `/pub` pages carry
    an add-to-cart control whose href is `javascript:addcart(…,'R-REP-BT.2526-1-2024-PDF-E',…)`,
    which contains both the edition id and `PDF-E`; the PDF match therefore
    requires a `.pdf`-terminated href (feeding the javascript one to `URI#merge`
    raises `URI::InvalidURIError` and killed a whole series).
  - **Recent reports have no anonymous PDF at all** — `R-REP-BT.2526-1-2024`
    offers only the cart flow — so `source` is legitimately empty for them.
  - **Missing before promotion:** no per-row rescue in `#harvest` (unlike
    `DataFetcher#spawn_rec_worker`), results accumulated in memory rather than
    streamed, and and `R-HDB` still unimplemented (see the handbook note above).
  - `status` is scraped (`In force (Main)` / `Superseded`) but **not** modelled —
    no published ITU-R record has one; it is the first candidate enrichment.
  - Same F5-WAF hardening as `#rec_agent` (browser UA, `max_history = 1`,
timeouts) plus a `delay:` politeness pause. Driven by
`DataFetcher#fetch_publications`; `itu.rb` still does not require it, so a
consumer-only load never pulls the crawler in.
- **Incremental write path (`DataMergeR`, `data_merge_r.rb`)** — the crawl is a
  *partial, lossier* view of the corpus, so a harvest must never be written as a
  rebuild. `DataMergeR.write_all(items, fetcher)` merges each record into the
  dataset and returns `{added:, backfilled:, unchanged:, skipped:, collisions:}`:
  - **`date` is never rewritten** (the 48/82 year-change measured above), and
    neither is anything else the published record already has. Only `title` and
    `source` are backfilled, and only when absent.
  - An unchanged record is **not rewritten at all** (byte-identical file, so the
    data repo's diff shows only real changes) but is still `index_primary`'d,
    because the index is rebuilt from scratch each run.
  - **Filename-collision guard.** ITU-R report and recommendation docids share a
    namespace (`ITU-R BO.1227-1` is a report; recommendations run through the
    same 1200s), so both map to `data/itu-r-bo-1227-1.yaml`. A harvested record
    whose published counterpart has a **different doctype** — or two harvested
    records claiming one filename — is logged via `Util.error` and **skipped**,
    never silently overwritten (which is what `#write_file`'s last-write-wins
    would do).
  - Verified end-to-end against real records (10 published BO files, both
    families, live harvest): 4 files rewritten, each changing **only** `source`;
    6 byte-identical; every published `date` preserved; no deletions.
  - **Corpus-scale dry run** (2026-08-13, against a writable copy of
    `relaton-data-itu`'s 5,334 ITU-R records; the checkout itself is read-only):
    recommendations 12/16 series in 49 min, reports 13/14 series in 126 min at a
    1 s delay. **213 records added** (34 recommendations — all pre-2024 gaps in
    the RunSearch-era crawl — and 179 reports, 8 of them published *after* the
    dataset froze, e.g. `ITU-R SM.2571-0`, 2026-08); **135 records backfilled, a
    `source` every one**; **0 dates changed and 0 records deleted**, across 3,600
    merged records. That is the invariant holding at corpus scale.
- **52 collisions — being resolved by giving Reports their own identity.**
  ITU-R Recommendations and Reports number independently but used to share this
  dataset's docid/filename namespace: `ITU-R BT.2020-1` is *both* Rec. BT.2020-1
  (06/2014, UHDTV parameter values) and Report BT.2020-1 (2000, objective
  quality assessment), so the published dataset holds whichever family the old
  crawler wrote last — 34 files hold the report and are missing the
  recommendation (incl. `BT.2020`, `M.2083` IMT Vision, `M.2134`), 18 the
  reverse. Since pubid #327 there is a `pubid:itu:report` type, so
  `DataParserR` now emits **`Report ITU-R BT.2020-1`** for the `R-REP` family
  (`#id_prefix`): the docid says which document it is, `output_file` derives
  `data/report-itu-r-*.yaml` from it, and the two can coexist. `DataMergeR`'s
  guard stays as the backstop for anything that still collides.

  **Not finished until the dataset migrates.** The published records still
  carry the old bare docids (984 of the 1,001 reports are indexed as
  `pubid:itu:recommendation`), so a lookup for `Report ITU-R BT.2020-1`
  resolves nothing until `relaton-data-itu` re-crawls onto the new names. Note
  the new filenames fall outside `data/itu-r-*.yaml`, the glob that repo's
  crawler passes to `#index_files` — it needs widening at the same time.
- **ITU-T harvester** (`#fetch_recommendations` + `DataParserT`) — added for issue
  relaton-itu#80. `#search_recs` issues **one** GET to
  `mws/api/recommendations/searchRecs?…&main_edition_flag=0&rows=100000&…`, which
  returns the whole ITU-T corpus as one row per edition (recommendations **and**
  supplements) — `{ "Total", "Data": [ { idrec, rec_name, title, approval_date,
  dms_link, status } ] }`. `DataParserT.parse` maps each row to an `ItemData`
  (`flavor: "itu"`): the primary docid is the **dated** `"ITU-T #{rec_name}"` (e.g.
  `"ITU-T A.1 (10/2000)"`, matching the `ITU-T L.163 (11/2018)` convention), so
  `Pubid::Itu` identifies each **edition** distinctly and index rows/filenames stay
  unique across editions (ITU-T editions differ by approval date, not a `-N` part).
  doctype is derived from `rec_name` markers (`Suppl`/`Amd`/`Cor`/`Annex` →
  `recommendation-{supplement,amendment,corrigendum,annex}`, else `recommendation`).
  A browser `User-Agent` (`USER_AGENT`) is sent because `www.itu.int` sits behind
  the same F5 WAF. Forms `Pubid::Itu` can't parse (e.g. `Annex` variants) are still
  written as data files but left unindexed and surfaced via `#report_errors`
  (same graceful degradation as `ITU-R RR`).
- **ITU-T enrichment** (`DataParserT.parse(row, agent, errors)`) — the searchRecs
  row is metadata-thin (docid/title/date/source/doctype), so each record is
  enriched to match the live runtime output: `#fetch_recommendations` builds a
  browser-UA Mechanize `agent` (F5 WAF) and passes it per row; `DataParserT`
  fetches `getRecHdrDetail?idrec=…` (via `RecommendationParser`) and adds the
  **abstract** (`summary`), **ISO/IEC co-identifier** (`iso_number`), **status**,
  **editorial-group + publisher contributors** (the editorial group from the
  `rec.aspx` workgroup page), the **edition** (`getRecEditions` → the row's own
  `Version`) and the **relations** (`hasEdition` per sibling edition,
  `complementOf` per `getRecSupplements` entry). The **date** is upgraded to
  day-precision from the row's `approval_date` (no extra call); **copyright** and
  the Geneva **place** are derived from the row alone (`#fetch_copyright`), so
  even an un-enriched record carries them. Enrichment is **best-effort** — a
  detail-fetch failure is logged and degrades to the thin record rather than
  losing it. It costs ~4 calls per record (`getRecHdrDetail`, `getRecEditions`,
  `getRecSupplements`, `rec.aspx`) — the bulk of the crawl — so progress is logged
  every 500 records. This is what makes an indexed runtime lookup as rich as the
  live one; the published dataset predates it (see **Runtime lookup** above).
- **Shared extractor `RecommendationFields`** (`recommendation_fields.rb`) — a
  mixin keyed on `agent`/`idrec`/`imp` hooks. The **`getRecHdrDetail`-sourced field
  extraction** (`fetch_titles`/`fetch_status`/`fetch_dates`/`fetch_abstract`/
  `fetch_source`/`fetch_relations`/`fetch_workgroup`) is **genuinely shared**:
  `RecommendationParser` is now Hit-agnostic (`new(agent, idrec, imp)`), `include`s
  the module, and is used by **both** the live path (`Scraper` builds it with
  `hit.hit_collection.agent`) and the harvester (`DataParserT`, via a
  `RecommendationParser` instance) — one implementation, so those fields can't
  drift. Path-specific bits stay in the concrete classes: row-based
  docid/title/date/doctype in `DataParserT`; `imp` handling in the live path.
  The module also carries `iso_docid`/`editorial_group`/`publisher`/
  `group_subdivision`, used by the **harvester**. NOTE: the live `Scraper` still
  keeps its own equivalent contributor/ISO logic (`fetch_editorial_contributor`/
  `fetch_publisher_contributors`/`group_subdivision`/`createdocid`) because that
  code also serves the RR/OB path — so those four are currently **parallel copies**
  kept in sync, not yet a single source. Fully folding `Scraper`'s recommendation
  contributors onto the module (guarding the RR/OB branch) is a deferred follow-up;
  it also converges naturally once the issue-75 live-path ISO change (`iso_number`)
  lands here.
- **Hosting:** both sectors live in the combined **`relaton/relaton-data-itu`** repo
  under one flat `data/` and one `pubid:itu` `index-v2` (published on `main`;
  ~21.5k records, ~20.5k indexed). Runtime consumers **are** repointed at it —
  `HitCollection::GH_ITU` — so `relaton-data-itu-r` is no longer read.

### Processor

`Relaton::Itu::Processor` extends `Relaton::Core::Processor` and is the entry point for the Relaton plugin system. Provides `get`, `fetch_data`, `from_xml`, `hash_to_bib`, `grammar_hash`, and `remove_index_file`.

### Pubid-backed index-v2

The ITU index is **pubid-structured** (`index-v2.yaml`/`.zip`, `INDEXFILE =
"index-v2"` in `lib/relaton/itu.rb`): each row's `:id` is a `Pubid::Itu::Identifier`
serialized to its `_type: pubid:itu:{recommendation,handbook,question,…}` hash in the
**flat, compact** shape (scalar `sector`/`series`/`number`/`parts` directly under
`_type`, e.g. `sector: R`, `number: '600'`, `parts: ['1']`) that the published
`relaton-data-itu` index-v2 carries (both sectors; `pubid:itu:supplement` and
`pubid:itu:amendment` rows come with the ITU-T half). That flat shape + the handbook/question
identifier types (and pubid #290's `matches?`/`exclude` fix) live on pubid `main`,
which the root `Gemfile` **temporarily pins** (see the pubid-pin note there) — it is
the same pubid that built the published index, so the flavor deserializes it (a
mismatched pubid produces the older nested shape and `Relaton::Index` rejects the
whole index).
The wiring mirrors NIST/ETSI/CIE:

- **Producer** (`DataFetcher`): `#index` calls `find_or_create(:itu, file:
  "#{INDEXFILE}.yaml", pubid_class: ::Pubid::Itu::Identifier)`; `#write_file`
  routes the primary id through `#index_primary`, which stores the **pubid object**
  (`index.add_or_update pid, file`) so `Relaton::Index` sorts by id number and
  serializes each id to its `_type:` hash on save.
- **The `#pubid` guard** parses via `::Pubid::Itu.parse` and additionally requires
  a lossless round-trip (`Identifier.from_hash(to_hash).to_hash == to_hash`, the
  index loader's own `Index::FileIO#id_supported?` acceptance test), returning nil
  otherwise. The pinned pubid models recommendations, **handbooks**
  (`ITU-R 23.HDB`), **questions** (`ITU-R 37-7/5:`), ITU-T `(V##)` versions and
  labelled `Annex`es (#320), and — since **#325** — every remaining ITU-T print
  form the corpus carries: `Technical Cor.`, Appendices, `bis`/`ter`
  (`ITU-T V.25 ter`), the D-series `R` suffix, series supplements, joint
  numbering, `Add. N`, and bare `v10`/`V2`/`v.1` versions. What the guard still
  skips is `ITU-R RR` (Radio Regulations, which the consumer serves via
  `#request_publication` anyway) and the malformed ITU-R docids described under
  **Index/data gap** below. The **published** index predates #325, so the gap
  closes on the next crawl. A skipped id is **not indexed** but
  its data file is still written; `#index_primary` records it in `#unparseable_ids`,
  and `#report_errors` (ISO-style) surfaces them at `:error` through the `gh_issue`
  channel, raising the "Error fetching documents" GitHub issue in CI
  (`ENV["GITHUB_REPOSITORY"]`). The published index-v2 carries ~5285 rows.
- **Consumer** (`HitCollection#index`, shared by `#request_document` and
  `#index_hits`): `find_or_create(:itu, url: "#{GH_ITU}#{INDEXFILE}.zip", file:,
  pubid_class: ::Pubid::Itu::Identifier)` against the **combined** repo — one index
  serves both sectors — then `index.search(pubid) { |i| index_match?(pubid, i[:id]) }`.
  The reference is passed as a pubid (not a String) so `Relaton::Index` narrows by
  document number (`id.root.number`) before the block. ITU-R parses via `#pubid_ref`
  (a ref pubid can't parse **raises** and propagates to the caller — relaton-cli /
  API callers rescue it — mirroring ETSI; the consumer no longer degrades to a
  raw-string substring search); ITU-T parses via `#index_pubid_ref`, which strips
  the edition date and **rescues** a parse failure to `nil`, because that path has
  a live fallback and a malformed reference (`ITU-T G.Suppl.47`) must warn and
  report "Not found", not raise.
- `#index_match?` delegates to pubid's structured `pubid.matches?(id, ignore:)`,
  ignoring `:parts` **only when the reference omits the part** — so a bare
  `ITU-R P.838` matches **every edition** (all `P.838-N`) while `ITU-R P.838-2`
  matches only that edition, and a bare `ITU-R M.1` does **not** match `ITU-R M.10`
  (a different document number, nor `-1` match `-10`) because pubid compares
  structured ids, not a `-`-anchored string. This mirrors the ETSI flavor's
  `Bibliography#best_match`; it works now that pubid #290 fixed
  `Pubid::Itu::Identifier#matches?`/`#exclude` (previously an
  `exclude`→`self.class.new` kwargs `ArgumentError`), replacing the earlier local
  anchored-`-` stopgap. It additionally ignores **`:year`/`:month`/`:version`**:
  ITU-T rows are one per dated (and possibly versioned) edition, so those are
  separable trailing components the reference is normalised away from — the same
  contract ETSI has (`omits: %i[version date]`) — and `Bibliography` narrows to
  the requested year/version afterwards. There is **no local series guard**: pubid
  #320 fixed `Supplement#==` to compare sector+series (before it, `ITU-T A Suppl. 2`
  matched every series' `Suppl. 2` — 42 rows — and the flavor carried a
  `same_document_family?` workaround). `#request_document`'s
  `max_by { |i| i[:id].code&.parts&.last.to_i }` then returns the latest edition by
  its numeric `code.parts` edition (pubid identifiers aren't Comparable, so a
  numeric key is needed; the index isn't ordered by edition).
- **Index/data gap — now ITU-R data quality only.** History: 979 unindexed → 755
  after two re-crawls → **47 after pubid #325**, which parses every ITU-T print
  form the dataset carries (`Technical Cor.`, Appendices, `bis`/`ter`, the
  D-series `R` suffix, series supplements, joint numbering, `Add. N`, bare
  `v10`/`V2`/`v.1` versions). Verified against `relaton-data-itu@9ecdaec5` with
  pubid `ac2fd517`: of the 755 then-unindexed records **708 index on the next
  crawl**, and re-parsing all 20,728 already-indexed ids produces **zero** hash
  changes — so no published index row changes shape.

  The 47 that remain are **all ITU-R**, and none is an identifier problem: they
  are malformed docids left by the decommissioned RunSearch crawler — series
  letters with no document number (`ITU-R BO`, `ITU-R BT`), Roman-numeral
  fragments (`ITU-R IV.IX`), study-group fragments (`ITU-R M.5-BL-13`) and
  trailing colons (`ITU-R 111-2:`). They have no number to key an index row on,
  so they are data to correct in `relaton-data-itu`, not identifiers to parse.

  relaton keeps exactly **one** normalisation (`DataParserT#normalize_rec_name`):
  a space where the series dot belongs (`G 231` → `G.231`, 4 records). pubid
  rejects that spelling deliberately — a space there is ambiguous against the
  series-only supplement form (`G Suppl. 1`) — so canonicalising it here is the
  agreed division of labour, not a workaround.
- **Processor** `#remove_index_file` passes the same `pubid_class:`.

The local `Relaton::Itu::Pubid` (a Parslet **ref** parser in `pubid.rb`) is
unrelated to the external `::Pubid::Itu` gem class used for indexing; both coexist
without collision.

## Testing

- **Index fixture:** `spec/fixtures/index-v2.zip` holds rows copied **verbatim**
  from the published `relaton-data-itu` `index-v2.zip` (`main`), so the specs stay
  honest about the production `_type: pubid:itu:*` shape — but trimmed to 5361 of
  its 20,472 rows, because deserializing the whole index costs ~37 s in
  `before(:suite)`. Kept: **every** ITU-R row (~5285) plus the ITU-T families the
  specs exercise, including deliberate decoys (`L.1630` next to `L.163`;
  `D Suppl. 2`/`G Suppl. 2` next to `A Suppl. 2`; `H.264.1` next to `H.264`) and the
  deliberate **absence** of `H.264 (V14)`, which is what exercises the live
  fallback. Regenerate with:

  ```ruby
  # ruby -rnet/http -ryaml -rzip -rstringio
  url  = "https://raw.githubusercontent.com/relaton/relaton-data-itu/refs/heads/main/index-v2.zip"
  keep = %w[itu-t-l-163- itu-t-l-1630- itu-t-z-100- itu-t-y-3500- itu-t-a-13-
            itu-t-a-suppl-2- itu-t-d-suppl-2- itu-t-g-suppl-2- itu-t-g-suppl-47-
            itu-t-g-989-2- itu-t-g-780-y-1351- itu-t-h-264-]
  Zip::File.open_buffer(StringIO.new(Net::HTTP.get(URI(url)))) { |z| @yaml = z.first.get_input_stream.read }
  rows = YAML.safe_load(@yaml, permitted_classes: [Symbol]).select do |r|
    b = File.basename(r[:file]); b.start_with?("itu-r-") || keep.any? { |p| b.start_with?(p) }
  end
  Zip::File.open("spec/itu/fixtures/index-v2.zip", Zip::File::CREATE) do |z|
    z.get_output_stream("index-v2.yaml") { |f| f.write rows.to_yaml }
  end
  ```

  It is loaded into the `Relaton::Index` pool in `before(:suite)`
  (`spec/support/webmock.rb`): the YAML is written to a temp file and read through
  `Relaton::Index::Type.new(:itu, nil, file, nil, ::Pubid::Itu::Identifier)`, and
  `type.index` forces the offline `pubid_class` deserialize before the net is
  blocked; `actual?` is overridden to match only the remote (`url:`) lookup. The
  fixture is **re-seated in `before(:each)`** because a producer-side
  `find_or_create(:itu, file:)` in another example evicts the url-serving entry
  from the shared pool (`Pool#type` replaces a non-`actual?` entry) — without the
  re-seat a later consumer lookup would rebuild a network-backed `Type` and hit the
  blocked net. The rows must deserialize under the pinned pubid — see the `Gemfile`
  pin note.
- **Crawler cassettes: one per example, and re-record this suite alone.** The
  `spec/itu/vcr_cassettes/itu_r_re*` cassettes back `data_crawler_r_spec.rb`, and
  each is owned by **exactly one example**. That is not stylistic: VCR re-records
  per cassette *insertion*, so a cassette shared across several examples is
  truncated to the first example's requests the moment the 7-day
  `re_record_interval` fires (verified — `itu_r_rec_bo` went 10 interactions → 1
  and took 15 examples down with it). If you add a crawler example, give it its
  own cassette rather than reusing one.

  `www.itu.int` sits behind a rate-limiting F5 WAF, so a refresh can bake a
  **block page** into a cassette instead of data — and ITU blocks the two path
  families differently: `/rec` answers **HTTP 503**, `/pub` answers a **302 to
  `notfound.aspx`**, which replays as a page with no rows rather than an error.
  That is the "recorded transport failure" case from the repo-root conventions:
  nothing to reconcile, just re-record. Re-record this suite **alone**
  (`cd spec/itu && bundle exec rspec -I . relaton/itu/data_crawler_r_spec.rb`),
  never under parallel `rake spec`, and sanity-check the counts afterwards — an
  empty series or a document count that collapsed to 0 is a block, not ITU
  deleting its corpus.
- **Framework:** RSpec with VCR cassettes for HTTP mocking and WebMock
- **Fixtures:** `spec/fixtures/` contains sample YAML/XML documents for round-trip tests
- **VCR cassettes:** `spec/vcr_cassettes/` — 19 cassettes recording real HTTP
  responses. VCR ignores only `index-v2.zip` (the index comes from the fixture
  above), so the per-record `raw.githubusercontent.com/…/data/*.yaml` GETs **are**
  recorded. Re-record by deleting the file and running the suite with network
  access; `re_record_interval` is 7 days, so a stale-cassette run refreshes them.
- **Coverage:** SimpleCov, target near 100%

Round-trip tests (serialize → deserialize → compare) are the primary pattern for model classes.

## Key Dependencies

- `relaton-bib` — base bibliographic model classes (`Bib::Item`, `Bib::Ext`, etc.)
- `relaton-core` — `Core::Processor`, `Core::DataFetcher` base classes
- `lutaml-model` — serialization framework (XML/YAML mapping via `Lutaml::Model::Serializable`)
- `mechanize` — web scraping for data fetching
- `relaton-index` — document indexing

## Ruby Version

Requires Ruby >= 3.1.0.
