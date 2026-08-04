# CLAUDE.md

## Development

- `bundle install` — install dependencies
- `bundle exec rake spec` — run tests
- `bundle exec rubocop` — lint

## Index (pubid-structured `index-v2`)

IEEE consumes and produces the **structured `index-v2`** (`INDEXFILE = "index-v2"`
in `lib/relaton/ieee.rb`): each row's `:id` is a `Pubid::Ieee::Identifier`
serialized to the `_type: pubid:ieee:*` (lutaml) form, keyed on the index via
`pubid_class: ::Pubid::Ieee::Identifier`.

- **Write side.** Unlike the doc-fetching pipeline, the index is built by a
  **separate step**: `Relaton::Ieee::DataFetcher.build_index(dir:, index_file:)`
  (`data_fetcher.rb`). It globs the per-document `data/*.yaml` files, extracts each
  primary non-trademark IEEE docidentifier, parses it via `.pubid` (a guarded
  `::Pubid::Ieee::Identifier.parse` + `from_hash(to_hash) == to_hash` round-trip
  check), `add_or_update`s the object, and `save`s. Ids pubid can't parse/round-trip
  are skipped; a per-file skip warning **and** a final
  `IEEE index-v2.yaml: N/M indexed, K skipped (P% coverage)` line are logged so the
  loss is never silent. `DataFetcher.fetch` (doc generation) is unchanged — the
  data repo (`relaton-data-ieee`) calls `build_index` after obtaining `data/`.
- **Read side.** `bibliography.rb#search` passes `pubid_class:` to `find_or_create`,
  parses the query with `parse_pubid` (falling back to the raw String on failure),
  passes the pubid to `index.search` for number-narrowing, and picks the row by
  `row[:id].to_s`. `processor.rb#remove_index_file` passes the same `pubid_class:`.

## Identifier resolution (`RawbibIdParser`, pubid-first)

`RawbibIdParser.parse(normtitle, stdnumber)` turns a raw IEEE catalog
`normtitle` into a **`::Pubid::Ieee::Identifier`** (`idams_parser.rb`/prefilter
consume `.to_s` / `.to_s(trademark: true)` / docnumber). It is **pubid-first**:
pubid parses ~93.5% of normtitles directly; the bespoke regex case statement
(`#parse_fallback`, ~430 lines) only normalizes the messy remainder into a
canonical string pubid then parses (→ 98.7% pubid objects, 100% coverage).

- **Faithfulness guard.** `#parse` always renders the bespoke reference
  (`parse_fallback(...).to_id`) and only accepts a pubid parse when it kept every
  non-date digit (`#faithful?`, a date-stripped **digit** multiset — digit-level
  so a benign re-split like `P1476/D4` vs `P14764` counts as faithful while a real
  loss like `/D3.0`→`/D.0` does not). If no pubid parse is faithful it returns the
  private fallback `Renderer` (the old bespoke id string) — so there is **zero
  silent digit loss**. ~1.3% of docs keep the `Renderer`.
- **No public `PubId` class.** The old `Relaton::Ieee::PubId` is gone; its
  rendering survives only as the private `RawbibIdParser::Renderer` used by the
  fallback. pubid (`::Pubid::Ieee::Identifier`) is the identifier abstraction.
- **Coordination with pubid.** IEEE ids now render in pubid's canonical form
  (`/D-5`→`/D5`, `802.16-2012 - Redline`, trademark `™`/`®` appended at the end,
  full corrigendum expansion). This required a batch of pubid fixes (draft-verbatim,
  redline, revision incl. numbered `RevN`, edition, trademark, historical formats,
  update_codes one-offs). `Core::DataFetcher#output_file` also sanitizes commas so
  pubid's `", Mar 2011"` dates don't leak into filenames.

## Fetch robustness (no silent corpus loss)

Amendment docnumbers can be pathologically long — pubid's `to_s` embeds the full
"(Amendment to … as amended by …)" clause (300+ chars). Two guards keep one such
id from silently halving the crawl (see the `data_fetcher.rb` history):

- **Bounded filenames.** `Core::DataFetcher#output_file` caps the basename at
  `MAX_BASENAME_BYTES` (255): when the sanitized id exceeds the OS limit it
  byte-truncates (`byteslice(…).scrub("")`, valid UTF-8) and appends a 12-char
  SHA1 of the **full** docid — bounded, unique, and **deterministic** so
  `save_doc`/`reconcile_staged_outputs`/`read_bib` all resolve the same name.
  Without this, `File.write` raised `Errno::ENAMETOOLONG`.
- **Per-document commit guard.** Both the serial (`run_shard`) and parallel
  (`spawn_batch` fork) paths route through one `commit_entry` helper that wraps
  `commit_doc` in a `rescue` (logs via `Util.error`, continues). A single bad doc
  no longer aborts a serial crawl, and a forked worker still reaches its
  `File.binwrite(state_path, …)` so `merge_state_files` sees its `saved_writes`
  and `reconcile_staged_outputs` doesn't delete the whole batch's staged files.
  Reconcile also logs the straggler-cleanup count so an anomaly isn't silent.

## Testing

- **Framework:** RSpec with VCR cassettes and WebMock.
- **Index fixture:** `spec/ieee/fixtures/index-v2.zip` (a small structured index for
  the read-spec targets) is deserialized through `::Pubid::Ieee::Identifier` and
  pre-loaded into the `Relaton::Index` pool in `before(:suite)`
  (`spec/ieee/support/webmock.rb`, NIST recipe). `index_builder_spec.rb` covers
  `build_index` (structured rows + skip logging).
- **VCR cassettes:** `spec/ieee/vcr_cassettes/` — `index-v2.zip` downloads are
  ignored by VCR (handled by the fixture).
