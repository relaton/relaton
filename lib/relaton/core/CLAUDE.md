# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-core is the foundation gem every flavor plugin builds on. It provides the abstract **`Relaton::Core::Processor`** base class (the registry plug-in interface), the search primitives (`HitCollection`, `Hit`), a parallel-fetch thread pool (`WorkersPool`), the crawl-politeness pair `Pacer` (shared request pacing) and `Governor` (pool-wide rate-limit back-pressure), the `DataFetcher` base for bulk ingest, and small parsing/utility mixins. It has no knowledge of any specific standards body.

## Development

```bash
bundle exec rake        # default task → rspec
bundle exec rspec spec/core/processor_spec.rb   # single file
bundle exec rubocop     # lint (rubocop-performance/-rake/-rspec)
```

## Architecture

Namespace: `Relaton::Core`. Key classes in `lib/relaton/core/`:

- **`Processor`** (`processor.rb`) — abstract base with the template methods every flavor implements: `get`, `fetch_data`, `from_xml`, `from_yaml`, `grammar_hash`, `threads`. Flavor processors subclass it and set `@short`/`@prefix`/`@defaultprefix`/`@datasets` in `initialize`.
- **`HitCollection`** (`hit_collection.rb`) — holds search results, delegates to an internal array, and uses `WorkersPool` to fetch items in parallel (4 workers by default). Uses `WeakRef` to avoid a circular reference back to its hits.
- **`Hit`** (`hit.rb`) — wraps one search result; its `item` is lazy-loaded on first access.
- **`DataFetcher`** (`data_fetcher.rb`) — abstract base for flavor bulk fetchers; provides `gh_issue` reporting (via `Relaton::Logger::Channels::GhIssue`), `output_file`, `unique_output_file`, `write_unique`, and `serialize` helpers.

  **Filename collisions.** `output_file` sanitizes `.`, `,`, `/`, `:`, `(`, `)`,
  `-` and whitespace all to `-`, so two **distinct** docids can map to one path
  — the live instance is relaton-data-iana's `rpki/signed-objects` and
  `rpki-signed-objects`, which both give `data/rpki-signed-objects.yaml`. A
  writer that merely warns and writes anyway leaves one file holding the wrong
  document for one of two index ids: a wrong answer, not a missing one.

  **`unique_output_file(docid)` is the write-path entry point.** It reserves and
  returns `output_file(docid)` when that path is free *or already belongs to the
  same docid*, and only a real clash with a **different** docid gets a variant
  suffixed with a digest of that docid. Two consequences worth keeping:

  - It is a **no-op for genuine duplicates**, so each flavor's own duplicate
    handling (skip / merge / last-wins) still fires exactly as before. That is
    what makes it safe to drop into an existing writer.
  - The suffix is keyed on the docid, not on encounter order, so adding a record
    never renames an existing file. (Which member of a clashing pair keeps the
    plain path does follow write order, which is stable for a given corpus.)

  **The genuine-duplicate check must come FIRST in an adopting writer.** Once a
  docid has been disambiguated, `unique_output_file` returns that suffixed path
  for it *forever*, so `file != output_file(docid)` stays true on every repeat.
  Gating the flavor's duplicate handling on that comparison makes it unreachable
  for a repeat, which silently drops a merge (3gpp) or a skip (ecma, jis). Use
  `@files.include?(file)` as the duplicate test — a reserved path only ever
  belongs to one docid — and use the `!= output_file` comparison only to decide
  what to log:

  ```ruby
  file = unique_output_file docid
  if @files.include? file
    <genuine duplicate: merge / skip / warn>
  else
    Util.warn "... writing #{file} instead" if file != output_file(docid)
    @files << file
    <write + index>
  end
  ```

  **`write_unique(docid, content)` closes the cross-PROCESS gap.**
  `unique_output_file` reserves in one process's `@file_docids`, which a forked
  worker cannot see. `write_unique` reserves, then creates the file with
  `O_EXCL` (`EXCLUSIVE = File::WRONLY | File::CREAT | File::EXCL`), and returns
  the path it actually wrote. Four outcomes:

  | situation | what happens |
  |---|---|
  | we already wrote this path for this docid | plain overwrite — a genuine duplicate stays one file |
  | `O_EXCL` succeeds | the normal case |
  | `EEXIST`, single process | `unique_output_file` already proved no peer of ours holds it, so it is a leftover from an earlier crawl: overwrite |
  | `EEXIST`, `@cross_process` | a peer's file and a leftover are indistinguishable: take the digest path instead |

  `@cross_process` defaults to false, so every single-process flavor takes the
  third row and behaves exactly as it did before adopting this. A fetcher that
  forks sets it **before** the first fork, so children inherit it — see
  `Relaton::Ietf::DataFetcher#fetch_ieft_internet_drafts`.

  A forked worker only learns that a path was taken, never *which* clashing
  docid deserves it, so the winner would follow the race and the two filenames
  would swap between crawls. The parent settles that afterwards, once it can see
  every docid: `Relaton::Ietf::DataFetcher#reconcile_output_files`.

  **Deliberately not a wall-clock staleness test.** `File.mtime(file) <
  run_started_at` looks like the obvious way to tell a leftover from a peer, and
  it is a trap: crawls run into a populated `data/`, so `EEXIST` is the *common*
  case on a re-run and the test would decide it for every record. Its
  false-"stale" direction is the silent overwrite this method exists to prevent,
  and coarse filesystem mtime granularity makes that reachable. Gating on
  `@cross_process` removes the failure class instead of tuning it.

  **Do not drop the unconditional `delete_suffix("-")` in `output_file`.** It is
  the root cause of the trailing-punctuation half of these collisions, and
  removing it would give the clashing ids distinct names — but it renames any id
  ending in a character the gsub maps to `-`. Measured over this repo's index
  fixtures (2026-08-26):

  | corpus | rows | filenames that would change |
  |---|---|---|
  | `spec/itu/fixtures/index-v2.zip` | 5,361 | **808** — ids ending `:`, e.g. `ITU-R 1-3/8:` |
  | `spec/nist/fixtures/index-v2.zip` | 19,515 | 2 — `NBS TN 467pt1 Add.` |
  | `spec/ietf/fixtures/ietf-index-v2.zip` | 177,362 | 3 |
  | `spec/iso` + `spec/iec` v2 | 112,189 | 0 |
  | every v1 string-id fixture | 97,966 | 7 — IEEE `IEEE 802.3-`, OGC `20-001r2 ` |

  A 15% rename of the published ITU corpus does not pay for collisions that
  `unique_output_file` and `write_unique` already close.

  **Audit of every `output_file` caller** (keep this exhaustive — it is the only
  place the decision is recorded):

  | Adopted | Abstains, and why |
  |---|---|
  | `iana`, `oasis`, `calconnect`, `xsf`, `nist`, `ecma`, `jis`, `3gpp`, `iec`, `etsi`; `ietf` via `write_unique` | `ieee` — `reconcile_staged_outputs` recomputes `output_file(docnumber)` in a later pass with no reservation state, so a disambiguated path breaks the staged rename |
  | | `itu`, `cie` — documented positional `@seen`/`pos` dedup under a parallel crawl |
  | | `iso` — `File.exist?` → `rewrite_with_same_or_newer` version compare |
  | | `ccsds` — `merge_links` merges into the existing file by design |

  Note `etsi` had **no** collision handling at all before this (silent overwrite,
  not even a warning), and `iec` had the warn-then-overwrite-anyway shape.
- **`WorkersPool`** (`workers_pool.rb`) — `SizedQueue`-backed thread pool for parallel work. **Runtime search only** — `HitCollection` uses it. No fetcher does: it carries no per-worker resources (a crawler needs one Mechanize agent per thread) and collects into an unsynchronised array. A crawler that needs a pool builds its own; see `Relaton::Itu::DataCrawlerR#in_parallel` and `Relaton::Cie::DataFetcher#process_hits`.
- **`Pacer`** (`pacer.rb`) — process-wide, thread-safe request pacer: the whole pool between them starts at most one request per `gap` seconds. **Shared, not per-worker** — that is the point, and the contrast with `Relaton::Cie::DataFetcher::Pacing`, whose gap is per worker (N workers there issue N requests per gap, which is right for CIE and wrong when the budget belongs to one host). A reservation never starts before "now", so an idle stretch cannot be repaid as a burst, and the mutex is never held across the sleep. `mode: :fixed` reproduces a plain `sleep delay` loop as a rollback knob. `clock:`/`sleeper:` are injectable, so the arithmetic is specced without wall-clock waits.
- **`Governor`** (`governor.rb`) — process-wide, thread-safe rate-limit back-pressure: one shared cooldown the whole pool observes, escalating per *round* (60 s → 900 s) rather than per worker, decaying on success, and latching a give-up after five barren rounds so a banned crawl fails fast instead of grinding out a CI job's remaining hours. Two round counters, deliberately: **`#throttle_rounds`** is the LIVE count since the last success (ITU logs it per retry as the current round) and `#succeeded!` resets it, while **`#give_up_rounds`** is the count snapshotted at the instant `@abandoned` latched, and is what an abort message must report — reading the live one after the latch names whatever re-accumulated since, which is how a W3C give-up at round 5 got logged as *"after 2 consecutive backoffs"*. Note also that `#wait` returning 0.0 once latched stops the pool *waiting*, not *asking*: a flavor must guard its own request sites (see `Relaton::W3c::SafeRealize#realize`) or a banned crawl keeps hammering the host until it winds down. Promoted here from `Relaton::W3c`. A flavor subclasses it and supplies two things: `THROTTLE_ERRORS` (or `.throttle?`, when the signal is a status code rather than an exception class, as for ITU) and `ENV_PREFIX`, which namespaces `<PREFIX>_THROTTLE_BASE/_MAX/_GIVEUP` so two flavors crawling in one process cannot share a ladder. Bindings: `Relaton::W3c::Governor`, `Relaton::Itu::Governor`.
- **Mixins** — `DateParser` (`parse_date` for "February 2012"/"2012-02-03"/etc.), `ArrayWrapper` (`array(x)` → always an Array), `HashKeysSymbolizer` (recursive string→symbol keys).

### How flavors consume it (important)

Every flavor's `Relaton::<Flavor>::Processor < Relaton::Core::Processor`. Because the umbrella registry now loads flavors lazily (only their `…/processor` file), any processor method that touches a flavor constant must `require_relative "../<flavor>"` first — see the root `CLAUDE.md` "Registry is lazy" note.

## External dependencies

`nokogiri ~> 1.16`, `psych ~> 5.2.0`, `relaton-logger ~> 2.2.0.pre.alpha.1`.

## Testing

RSpec with SimpleCov. Specs live under `spec/core/` and mirror the lib classes; `spec/support/` defines dummy processor/types for exercising the base classes.
