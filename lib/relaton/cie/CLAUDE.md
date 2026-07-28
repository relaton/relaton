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

## Crawler (`data_fetcher.rb`) — parallel detail fetch

The Techstreet crawl (~1147 docs) is a headless-Chrome (Ferrum) scrape. It runs in
**two phases**:

- **Phase 1 — `collect_hits` (serial):** page through the search results following
  `//a[@class="next_page"]`, collecting every `//li[@data-product]` into one list
  (~12 page loads at `per_page=100`).
- **Phase 2 — `process_hits` (parallel):** fan the hits out over a bounded pool.
  **Each worker owns its own `BrowserAgent`** (its own Chrome, built via the
  `build_agent` factory so the full UA/header + `navigator`/`window.chrome` stealth
  masking runs per worker — Cloudflare evasion must hold per worker, not for a shared
  singleton). Agents are built up front on the main thread (a Chrome-launch failure
  aborts fast instead of hanging the bounded queue) and **every** agent is quit in an
  `ensure`. The single memoized `#agent` is used only for Phase 1.

**Concurrency knob:** `RELATON_CIE_CONCURRENCY` (default **5**, min 1), read by
`.concurrency`. `relaton-data-cie`'s crawler workflow tunes it via env — no code change.

**Per-worker adaptive pacing (`Pacing`)** replaces the old single global 4 s gap: each
worker starts at `BASE_GAP` (~1 s) and **doubles its own gap up to `MAX_GAP`** only on
trouble — a Cloudflare challenge or a Ferrum/socket error (`RETRIABLE_ERRORS`).
`BrowserAgent#wait_for_challenge` raises a retriable `ChallengeError` when the challenge
doesn't clear within `MAX_CHALLENGE_WAIT`, so a stuck worker backs off and retries
(`#time_req` keeps the 4-try retry) instead of parsing the challenge HTML.

**Thread-safety & byte-identical output:** the slow `agent.get` runs lock-free; the
cheap build + `#write_file` run under one `@mutex`, so `@files`/`@errors`/`@seen` and the
index mutate single-threaded. Output is order-independent by construction — `@errors`
accumulates with `&&=` (AND, per-doc build is atomic under the lock), `@files` is a Set,
and the structured index is sorted deterministically on save. For a duplicate output
file, a `@seen[file] => catalogue-position` guard (`#superseded?`) keeps the
**last-by-position** content winner the serial crawl would pick; `index.add_or_update`
runs for **every** distinct id *before* that gate, so each id is still indexed. `index.save`
is called **once**, after the pool drains.

## Development

- `bundle install` — install dependencies
- `bundle exec rake spec` — run tests
- `bundle exec rubocop` — lint

## Testing

- **Framework:** RSpec with VCR cassettes and WebMock
- **Index fixture:** `spec/fixtures/index-v2.zip` (the published structured index) is loaded through a `Relaton::Index::Type` with `::Pubid::Cie::Identifier` and injected into the `Relaton::Index` pool in `before(:suite)` (see `spec/support/webmock.rb`, mirroring NIST/ETSI). Run `rake spec:update_index` to refresh from relaton-data-cie.
- **VCR cassettes:** `spec/vcr_cassettes/` — index download requests are ignored by VCR (handled by fixture).
