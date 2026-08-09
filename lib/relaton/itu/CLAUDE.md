# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-itu is a Ruby gem for retrieving ITU (International Telecommunication Union) standards metadata. Part of the Relaton family of gems maintained by Ribose Inc.

## Commands

```bash
bundle exec rake spec          # Run full test suite
bundle exec rspec spec/relaton/itu/              # Run new-namespace tests only
bundle exec rspec spec/relaton/itu/item_spec.rb  # Run a single spec file
bundle exec rspec spec/relaton/itu/item_spec.rb:15  # Run a specific test by line
bin/console                    # Interactive Ruby console with gem loaded
```

No separate lint command is configured; RuboCop can be run via `bundle exec rubocop`.

## Architecture

### Namespace Migration (In Progress)

The codebase is migrating from flat `RelatonItu` namespace (`lib/relaton_itu/`) to nested `Relaton::Itu` (`lib/relaton/itu/`). Both namespaces coexist:

- **`lib/relaton/itu/`** — New namespace. Model classes, DataFetcher, DataParserR, Processor, Bibliography, HitCollection, Util, Version are here.
- **`lib/relaton_itu/`** — Old namespace. ItuBibliography, XMLParser, ItuBibliographicItem, and others still live here.

The `Processor` class (`Relaton::Itu::Processor`) bridges both: it lives in the new namespace but calls old-namespace classes (`::RelatonItu::ItuBibliography`, `::RelatonItu::XMLParser`, etc.) for functionality not yet migrated.

### Model Layer (Lutaml::Model)

All model classes use `Lutaml::Model::Serializable` for XML/YAML serialization:

- **`Item`** → extends `Bib::Item` (main bibliographic item)
- **`ItemData`** → extends `Bib::ItemData` (used by DataParserR for parsed documents)
- **`Bibitem`** / **`Bibdata`** → extend `Item`, mix in shared behavior from `Bib`
- **`Ext`** → extends `Bib::Ext` with ITU-specific fields (doctype, structuredidentifier, question, recommendationstatus, ip_notice_received, meeting, meeting_place, meeting_date, intended_type, source)
- **`Doctype`**, **`StructuredIdentifier`**, **`EditorialGroup`**, **`Bureau`**, **`Group`**, **`ApprovalStage`**, **`RecommendationStatus`**, **`Question`**, **`Meeting`**, **`MeetingDate`** — ITU-specific metadata types

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
  and **editorial-group + publisher contributors** (the editorial group from the
  `rec.aspx` workgroup page). The **date** is upgraded to day-precision from the
  row's `approval_date` (no extra call). Enrichment is **best-effort** — a
  detail-fetch failure is logged and degrades to the thin record rather than
  losing it. This is ~one `getRecHdrDetail` (+ one `rec.aspx`) per record — the
  bulk of the crawl's cost — so progress is logged every 500 records.
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
- **Hosting:** the ITU-T harvest is destined for a **new combined
  `relaton/relaton-data-itu` repo** (both sectors share one `pubid:itu` `index-v2`);
  runtime consumers are not yet repointed at it. See the repo-root hand-off
  `relaton__relaton-data-itu__create-combined-dataset-repo.md`.

### Processor

`Relaton::Itu::Processor` extends `Relaton::Core::Processor` and is the entry point for the Relaton plugin system. Provides `get`, `fetch_data`, `from_xml`, `hash_to_bib`, `grammar_hash`, and `remove_index_file`.

### Pubid-backed index-v2

The ITU index is **pubid-structured** (`index-v2.yaml`/`.zip`, `INDEXFILE =
"index-v2"` in `lib/relaton/itu.rb`): each row's `:id` is a `Pubid::Itu::Identifier`
serialized to its `_type: pubid:itu:{recommendation,handbook,question,…}` hash in the
**flat, compact** shape (scalar `sector`/`series`/`number`/`parts` directly under
`_type`, e.g. `sector: R`, `number: '600'`, `parts: ['1']`) that the published
`relaton-data-itu-r` index-v2 carries. That flat shape + the handbook/question
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
  (`ITU-R 23.HDB`) and **questions** (`ITU-R 37-7/5:`), so the guard only skips the
  few residual forms it can't parse (e.g. `ITU-R RR`, Radio Regulations — which the
  consumer serves via `request_search` anyway). A skipped id is **not indexed** but
  its data file is still written; `#index_primary` records it in `#unparseable_ids`,
  and `#report_errors` (ISO-style) surfaces them at `:error` through the `gh_issue`
  channel, raising the "Error fetching documents" GitHub issue in CI
  (`ENV["GITHUB_REPOSITORY"]`). The published index-v2 carries ~5285 rows.
- **Consumer** (`HitCollection#request_document`): `find_or_create(:itu, url:
  "#{GH_ITU_R}#{INDEXFILE}.zip", file:, pubid_class: ::Pubid::Itu::Identifier)`,
  then `index.search(pubid) { |i| part_match?(pubid, i[:id]) }`. The reference is
  parsed to a `::Pubid::Itu::Identifier` by `#pubid_ref` (a ref pubid can't parse
  **raises** and propagates to the caller — relaton-cli / API callers rescue it —
  mirroring ETSI; the consumer no longer degrades to a raw-string substring
  search) and passed as a pubid (not a String) so `Relaton::Index` narrows by
  document number (`id.root.number`) before the block. `#part_match?` delegates to
  pubid's structured `pubid.matches?(id, ignore:)`, ignoring `:parts` **only when
  the reference omits the part** — so a bare `ITU-R P.838` matches **every edition**
  (all `P.838-N`) while `ITU-R P.838-2` matches only that edition, and a bare
  `ITU-R M.1` does **not** match `ITU-R M.10` (a different document number, nor
  `-1` match `-10`) because pubid compares structured ids, not a `-`-anchored
  string. This mirrors the ETSI flavor's `Bibliography#best_match`; it works now
  that pubid #290 fixed `Pubid::Itu::Identifier#matches?`/`#exclude` (previously an
  `exclude`→`self.class.new` kwargs `ArgumentError`), replacing the earlier local
  anchored-`-` stopgap. `max_by { |i| i[:id].code&.parts&.last.to_i }` then returns
  the latest edition by its numeric `code.parts` edition (pubid identifiers aren't
  Comparable, so a numeric key is needed; the index isn't ordered by edition).
- **Processor** `#remove_index_file` passes the same `pubid_class:`.

The local `Relaton::Itu::Pubid` (a Parslet **ref** parser in `pubid.rb`) is
unrelated to the external `::Pubid::Itu` gem class used for indexing; both coexist
without collision.

## Testing

- **Index fixture:** `spec/fixtures/index-v2.zip` is the **published**
  `relaton-data-itu-r` `index-v2.zip` verbatim (the `v2` branch; ~5285 flat
  `_type: pubid:itu:*` rows) — using the real index keeps the specs honest about the
  production shape. It is loaded into the `Relaton::Index` pool in `before(:suite)`
  (`spec/support/webmock.rb`): the YAML is written to a temp file and read through
  `Relaton::Index::Type.new(:itu, nil, file, nil, ::Pubid::Itu::Identifier)`, and
  `type.index` forces the offline `pubid_class` deserialize before the net is
  blocked; `actual?` is overridden to match only the remote (`url:`) lookup. The
  fixture is **re-seated in `before(:each)`** because a producer-side
  `find_or_create(:itu, file:)` in another example evicts the url-serving entry
  from the shared pool (`Pool#type` replaces a non-`actual?` entry) — without the
  re-seat a later consumer lookup would rebuild a network-backed `Type` and hit the
  blocked net. Refresh it by re-downloading the published `index-v2.zip` (it must
  deserialize under the pinned pubid — see the `Gemfile` pin note).
- **Framework:** RSpec with VCR cassettes for HTTP mocking and WebMock
- **Fixtures:** `spec/fixtures/` contains sample YAML/XML documents for round-trip tests
- **VCR cassettes:** `spec/vcr_cassettes/` — 22 cassettes recording real HTTP responses
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
