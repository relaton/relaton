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

- **`lib/relaton/itu/`** — New namespace. Model classes, DataFetcher, DataParserR, Processor, Util, Version are here.
- **`lib/relaton_itu/`** — Old namespace. ItuBibliography, XMLParser, ItuBibliographicItem, HitCollection, and others still live here.

The `Processor` class (`Relaton::Itu::Processor`) bridges both: it lives in the new namespace but calls old-namespace classes (`::RelatonItu::ItuBibliography`, `::RelatonItu::XMLParser`, etc.) for functionality not yet migrated.

### Model Layer (Lutaml::Model)

All model classes use `Lutaml::Model::Serializable` for XML/YAML serialization:

- **`Item`** → extends `Bib::Item` (main bibliographic item)
- **`ItemData`** → extends `Bib::ItemData` (used by DataParserR for parsed documents)
- **`Bibitem`** / **`Bibdata`** → extend `Item`, mix in shared behavior from `Bib`
- **`Ext`** → extends `Bib::Ext` with ITU-specific fields (doctype, structuredidentifier, question, recommendationstatus, ip_notice_received, meeting, meeting_place, meeting_date, intended_type, source)
- **`Doctype`**, **`StructuredIdentifier`**, **`EditorialGroup`**, **`Bureau`**, **`Group`**, **`ApprovalStage`**, **`RecommendationStatus`**, **`Question`**, **`Meeting`**, **`MeetingDate`** — ITU-specific metadata types

### Data Fetching

- **`DataFetcher`** extends `Core::DataFetcher` — orchestrates fetching ITU-R documents from `extranet.itu.int`
- **`DataParserR`** — module that parses ITU-R JSON search API results into `ItemData` instances (sets `flavor: "itu"` on all parsed documents)
- Sources: recommendations (JSON index), questions, reports, handbooks, resolutions (HTML indices)

### Processor

`Relaton::Itu::Processor` extends `Relaton::Core::Processor` and is the entry point for the Relaton plugin system. Provides `get`, `fetch_data`, `from_xml`, `hash_to_bib`, `grammar_hash`, and `remove_index_file`.

### Pubid-backed index-v2

The ITU index is **pubid-structured** (`index-v2.yaml`/`.zip`, `INDEXFILE =
"index-v2"` in `lib/relaton/itu.rb`): each row's `:id` is a `Pubid::Itu::Identifier`
serialized to its `_type: pubid:itu:{recommendation,handbook,question,…}` hash in the
**flat, compact** shape (scalar `sector`/`series`/`number`/`parts` directly under
`_type`, e.g. `sector: R`, `number: '600'`, `parts: ['1']`) that the published
`relaton-data-itu-r` index-v2 carries. That flat shape + the handbook/question
identifier types live on the pubid `feat/itu-questions-handbooks` branch, which the
root `Gemfile` **temporarily pins** (see the pubid-pin note there) — it is the same
pubid that built the published index, so the flavor deserializes it (a mismatched
pubid produces the older nested shape and `Relaton::Index` rejects the whole index).
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
  parsed to a `::Pubid::Itu::Identifier` (string fallback via `#pubid_ref`) and
  passed as a pubid (not a String) so `Relaton::Index` narrows by document number
  (`id.root.number`) before the block. `#part_match?` then matches **every edition
  when the reference omits the part** (a bare `ITU-R P.838` → all `P.838-N`) and the
  exact edition when it names one — anchored on the `-` part separator, so a bare
  `ITU-R M.1` does **not** also match `ITU-R M.10` (nor `-1` match `-10`) the way a
  plain substring would. (pubid's own `matches?(ignore:)` is currently broken for
  ITU — `exclude` reconstructs via `self.class.new` and hits a Ruby-3 kwargs
  `ArgumentError` — hence the local anchored match rather than the ETSI
  `ignore: :part` form.) `max_by { |i| i[:id].code&.parts&.last.to_i }` then returns
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
