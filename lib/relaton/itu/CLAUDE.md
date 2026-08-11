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
  fallback is **load-bearing**, not a safety net: ~930 ITU-T data files are
  unindexed in the **published** index because the crawl that built it ran with a
  pubid that couldn't round-trip `(V##)`/`Annex` forms — e.g. the
  `ITU-T H.264 (V14) (08/2021)` record the specs ask for (pubid #320 parses both
  now, so a re-crawl closes this), Implementers' Guides
  (`ITU-T G.Imp712`) aren't harvested at all, and newly approved editions appear on
  `rec.aspx` before the next crawl. It triggers when the index has **no** row *or*
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
- **Metadata asymmetry, temporary:** an indexed Recommendation is only as rich as
  the published data record, and today's `relaton-data-itu` was crawled before the
  enriched `DataParserT` (below) — so no abstract, ISO co-identifier, contributors,
  status, edition or relations. A live-fallback record has all of them. Two
  `spec/relaton/itu_spec.rb` examples (`itu_t_y_3500`, `itu_t_a_13`) are relaxed
  with a `TODO` until the data repo re-crawls; see the repo-root hand-off
  `relaton__relaton-data-itu__recrawl-with-enriched-dataparsert.md`.

### Data Fetching

- **`DataFetcher`** extends `Core::DataFetcher`. `#fetch(source)` routes on the
  dataset name (from `Processor#@datasets = %w[itu-r itu-t]`): `"itu-t"` →
  `#fetch_recommendations`, everything else (`"itu-r"`, `nil`) →
  `#fetch_publications` (the legacy path). `index.save` + `report_errors` run once
  in `#fetch` after either harvester.
- **ITU-R harvester** (`#fetch_publications` + `DataParserR`) — paginates the
  `net4/.../RunSearch` endpoint and parses ITU-R JSON results. **This endpoint is
  WAF-dead** (F5 "Request Rejected"); the ITU-R crawler is broken pending a
  replacement enumeration source (see the repo-root hand-offs).
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
  (`ITU-R 23.HDB`), **questions** (`ITU-R 37-7/5:`) and — since #320 — ITU-T
  `(V##)` versions and labelled `Annex`es, so the guard now skips only the residual
  forms it still can't parse, chiefly `ITU-R RR` (Radio Regulations, which the
  consumer serves via `#request_publication` anyway) and the space-separated `ter`
  suffix (`ITU-T V.25 ter`). The **published** index predates #320, hence the
  ~930-file gap below. A skipped id is **not indexed** but
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
- **Index/data gap (stale, closes on re-crawl):** the crawler only indexes ids that
  round-trip through `::Pubid::Itu`, and the pubid that built the **published**
  index parsed neither `(V##)` nor `Annex` — so ~979 of the 21,451 data files (930
  ITU-T) have no index row and are reachable only through the ITU-T live fallback.
  pubid #320 parses both, so re-crawling `relaton-data-itu` closes it; the fallback
  then only covers Implementers' Guides and records newer than the last crawl.
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
