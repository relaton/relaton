# CLAUDE.md

## Index format (pubid v2 — structured `_type:` index)

CIE consumes and produces the **structured `index-v2`** (`INDEXFILE = "index-v2"`):
each row's `:id` is a `Pubid::Cie::Identifier` object, serialized by `relaton-index`
as a `_type: pubid:cie:…` map (mirrors the NIST/ETSI flavors).

- **Producer** (`data_fetcher.rb`): `#index` passes `pubid_class:
  ::Pubid::Cie::Identifier`; `#write_file` parses each docid via the `#pubid` helper
  and indexes the **object** (not the raw string). `#pubid` returns `nil` — the id is
  written to disk as a document but **left out of the index** — for any id pubid can't
  parse **or** that doesn't round-trip. The guard mirrors the read side's acceptance
  test (`Index::FileIO#id_supported?`, `from_hash(to_hash) == to_hash`): the loader
  rejects the *whole* index on the first non-round-tripping row, so a bad id must be
  dropped at write time rather than poison every lookup.
- **Consumer** (`scrapper.rb`, `processor.rb`): both pass `pubid_class:
  ::Pubid::Cie::Identifier` to `Index.find_or_create`. The scrapper parses the ref to a
  pubid (`#parse_pubid`, falling back to the raw String on a partial/unparseable ref)
  and passes **that** to `index.search` so index-v2 narrows candidates by number via
  binary search before the block runs (a String arg would force a full O(n) scan — see
  `Index::Type#search_candidates`); the block keeps the broad substring match, and
  `min_by { |r| r[:id].to_s }` picks the winner (rows are pubid objects, not
  `Comparable`, so compare by string form). The scrapper's `ENDPOINT` targets the data
  repo's **`v2`** branch, so it fetches `…/v2/index-v2.zip`.

### pubid dependency

The published `relaton-data-cie/index-v2` uses CIE **proceedings** ids
(`_type: pubid:cie:proceedings` with `paper`/`page_range`) and the **flattened**
`to_hash` (`number`/`year` scalar, no nested `code`). That support is on pubid **`main`**
but **not** in the released `2.0.0.pre.alpha.8` that `relaton.gemspec` pins — the
released pubid strips `paper`/`page_range` and emits the nested shape, so
`Relaton::Index` would reject the whole published index. So the root `Gemfile`
temporarily pins `pubid` to `git: …/pubid.git, branch: main` (shared with the ETSI/JCGM
flavors); revert to the released pubid once these ship in a pubid release.

Note the CIE grammar extensions **do** parse the techstreet variant ids like
`CIE x051:2025/zcunvy` (as `Conference` `@variant` ids), so — unlike the old pubid —
they are indexed, not dropped.

## Development

- `bundle install` — install dependencies
- `bundle exec rake spec` — run tests
- `bundle exec rubocop` — lint

## Testing

- **Framework:** RSpec with VCR cassettes and WebMock
- **Index fixture:** `spec/fixtures/index-v2.zip` (the published structured index) is loaded through a `Relaton::Index::Type` with `::Pubid::Cie::Identifier` and injected into the `Relaton::Index` pool in `before(:suite)` (see `spec/support/webmock.rb`, mirroring NIST/ETSI). Run `rake spec:update_index` to refresh from relaton-data-cie.
- **VCR cassettes:** `spec/vcr_cassettes/` — index download requests are ignored by VCR (handled by fixture).
