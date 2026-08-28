# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-w3c is a Ruby gem for retrieving and representing W3C Standards bibliographic data using the Relaton model. It is part of the larger Relaton ecosystem of gems. Uses a LutaML-based model architecture under the `Relaton::W3c` namespace.

## Common Commands

```bash
# Install dependencies
bundle install

# Run all tests
bundle exec rake spec

# Run a specific test file
bundle exec rspec spec/relaton/w3c/item_spec.rb

# Run a specific test by line number
bundle exec rspec spec/relaton/w3c/item_spec.rb:7

# Lint
bundle exec rubocop

# Interactive console
bin/console
```

## Architecture

### Class Hierarchy

All classes live under `lib/relaton/w3c/` in the `Relaton::W3c` namespace:

**Model classes:**
- **`Item`** (`item.rb`) — extends `Bib::Item`, adds W3C `ext` attribute. Base class for both Bibitem and Bibdata.
- **`ItemData`** (`item_data.rb`) — LutaML data model for `Item`
- **`Bibitem`** (`bibitem.rb`) — extends `Item`, includes `Bib::BibitemShared` (XML serialization without `<bibdata>` wrapper)
- **`Bibdata`** (`bibdata.rb`) — extends `Item`, includes `Bib::BibdataShared` (XML serialization with `<bibdata>` wrapper)
- **`Ext`** (`ext.rb`) — extends `Bib::Ext`, adds W3C-specific `doctype` attribute
- **`Doctype`** (`doctype.rb`) — extends `Bib::Doctype`, restricts content to `groupNote` or `technicalReport`

**Public API:**
- **`Bibliography`** (`bibliography.rb`) — search and retrieve W3C standards from the Relaton index. Parses the reference with `Pubid::W3c` and narrows the index by number before matching; see **Index (`index-v2`, pubid-keyed)**.
- **`Processor`** (`processor.rb`) — extends `Relaton::Core::Processor`, registers the W3C flavor (prefix `W3C`, dataset `w3c-api`)

**Data fetching:**
- **`DataFetcher`** (`data_fetcher.rb`) — extends `Core::DataFetcher`, fetches all W3C specs via the W3C API. Fetches the specification index with `embed: true` so each spec is realized from the page's embedded payload instead of a per-spec HTTP request, and paginates by page number (only the `fetch` path repopulates `_embedded`, unlike realizing the `next` link). Runs `fetch_spec` across a small thread pool. A SIGINT (Ctrl-C) is handled gracefully — the producer stops queuing and workers stop after their in-flight spec, then the index of everything fetched so far is saved (the prior INT handler is restored afterwards, so the trap doesn't leak into the host process). The crawl refuses to save a truncated dataset — `crawler.rb` wipes `data/` before each run, so saving one commits mass deletions. Three guards enforce that, all raising `CrawlIncompleteError`: an index page that fails after retries or pagination ending before the API's advertised last page (`enqueue_specs`); the governor concluding the crawl is banned (`guard_rate_limited`); and more than `max_throttled_losses` resources dropped to rate limiting (`guard_throttle_budget` — the per-resource counterpart, since pagination can complete cleanly while the documents behind it were quietly hollowed out). A **deliberate** `@interrupted` (Ctrl-C) is exempt: it already means "give me what you have". The worker pool is still drained in an `ensure` so an abort doesn't deadlock. See **Crawler tuning** for the env-var knobs.
- **`DataParser`** (`data_parser.rb`) — converts W3C API spec objects into `Relaton::W3c::Item` instances
- **`Governor`** (`governor.rb`) — the W3C binding of **`Relaton::Core::Governor`**, which is where process-wide, thread-safe rate-limit back-pressure now lives (see Rate limiting & retries). It was promoted out of this flavor when the ITU-R crawler became the second consumer. What stays here is only what W3C knows: `THROTTLE_ERRORS` (429 **and** 403, the lutaml-hal classes core must not depend on) and `ENV_PREFIX = "RELATON_W3C"`. The ladder, the per-round escalation, the jitter, the latched give-up and the `Retry-After` parsing are core's, and `spec/w3c/relaton/w3c/governor_spec.rb` still exercises all of it through this subclass unchanged — which is the promotion's acceptance test.
- **`SafeRealize`** (`safe_realize.rb`) — mixin that, on a terminal error, skips the resource (returns `nil`) so one bad link doesn't abort the crawl, and that routes rate limiting through the `Governor` instead (see Rate limiting & retries). It does not cache successes — that lives upstream.
- **`Docidentifier`** (`docidentifier.rb`) — `Bib::Docidentifier` subclass that parses its `content` into a `Pubid::W3c::Identifier` and exposes it as `#pubid`. See **Index (`index-v2`, pubid-keyed)**.
- **`PubId`** (`pubid.rb`) — the **legacy `index-v1` row shape**, no longer on any lookup or crawl path here. Retained public only so `relaton-data-w3c`'s crawler can keep emitting `index-v1` for released relaton v2 consumers (the `Relaton::Bipm::Id` precedent). Do not add call sites.

**Utilities:**
- **`Util`** (`util.rb`) — extends `Relaton::Bib::Util`, sets `PROGNAME` for logging

The entry module is defined in `lib/relaton/w3c.rb` and exposes `grammar_hash`.

### Crawler tuning

`DataFetcher` is tunable via environment variables (read by class methods, so they apply to the whole crawl):

- **`RELATON_W3C_FETCH_CONCURRENCY`** (default `4`) — number of `fetch_spec` worker threads. Kept conservative so the version-history requests don't burst fast enough to trip the W3C API rate limiter (429s); raise it for a faster run, lower it for debugging or if 429 skips appear.
- **`RELATON_W3C_FETCH_VERSIONS`** (default enabled) — set to `false`/`0`/`no`/`off` for a faster, shallower crawl that emits only the top-level specifications and skips each spec's version-history fan-out (version_history, predecessor/successor versions — the bulk of the API requests). Leave it set (the default) for a complete dataset.
- **`RELATON_W3C_THROTTLE_BASE`** / **`_MAX`** / **`_GIVEUP`** (defaults `60` / `900` / `5` — see `Governor`) — first cooldown, cooldown ceiling, and how many consecutive throttle rounds without a success end the crawl. Non-positive values are ignored. These three are read by the governor on construction **and on each `SafeRealize.reset!`** (i.e. at the start of every `fetch`), so like the others they can be set any time before the crawl rather than before the flavor is autoloaded.
- **`RELATON_W3C_MAX_THROTTLED`** (default `25`) — how many resources may be lost to rate limiting before `fetch` refuses to save the index. `0` is accepted and means "tolerate none".

`embed: true` (always on) inlines each specification into its index page, so the per-spec realize is served from memory rather than an HTTP request — the largest single reduction in request count.

### Rate limiting & retries

Per-request retries are layered upstream; **pool-wide back-pressure is this
gem's job** (`Governor`), because upstream has no notion of the crawl as a whole.

- **w3c_api** (>= 0.3.3, pinned in the gemspec) builds its HAL client with
  `faraday-retry` for HTTP 403 — the W3C rate-limit signal — plus
  connection/timeout errors, and sends an identifying `User-Agent`. Both landed
  in 0.3.3 (relaton/w3c_api#22, #23); before it, requests went out as
  `Faraday v2.x` (a Cloudflare bot-heuristic trigger, and the most likely reason
  a crawl flipped into the banned mode at all) and the 403 retry never fired.
- **lutaml-hal** (>= 0.2.5, declared directly in the gemspec because this flavor
  rescues its error classes by name) retries 429 and 5xx with exponential
  backoff. `DataFetcher` **shortens** that policy via
  `W3cApi::Hal.instance.configure_rate_limiting(UPSTREAM_RATE_LIMITING)`: its
  defaults burn ~31 s (1+2+4+8+16) before a 429 ever reaches us, which only
  delays the back-pressure that actually works. `max_retries` stays at 5 — one
  count covers both 429 and 5xx, and a 5xx is still a permanent skip here.
  From 0.3.3 that call rebuilds w3c_api's register itself; **don't** follow it
  with `reset_register`, which would leave the register absent from lutaml-hal's
  `GlobalRegister`, where `Link#realize` raises.

**`Governor` (`governor.rb`) is the important piece.** `api.w3.org` is behind
Cloudflare, whose rate limiting is **bimodal**: a run either never trips it or
trips it and stays banned for hours. Second-scale backoff cannot climb out of
that, and per-worker backoff is worse than useless — the retries are what keep
the limiter engaged. So all workers share one cooldown:

- Any thread seeing a 429 opens/extends it; every other thread observes it in
  `#wait`. Cooldowns escalate **per round** (60 s → 120 → … → 900 s cap), where a
  "round" is one open cooldown — four workers tripping the same limiter must not
  fast-forward the ladder four steps.
- A `Retry-After` header raises the floor but never lowers our own ladder, and is
  itself capped (a hostile value must not park a worker for an hour). Both RFC
  9110 forms are honoured: delta-seconds, and an HTTP-date parsed properly
  (digit-scanning one would pick up the day-of-month).
- A success calls `#succeeded!`, which clears the cooldown and **decays**
  (halves) the penalty rather than resetting it, so a flapping limiter still
  climbs. **Only a realize that actually went to the network counts** — with a
  `parent_resource`, lutaml-hal serves the object out of the page's `_embedded`
  payload and issues no request (`link.rb`: *"Priority 1: check embedded content
  first"*). That is the common path, one per specification, and counting those
  would reset the ladder between every pair of version-history 429s, so the
  governor could never reach its threshold.
- After `GIVE_UP_AFTER` consecutive rounds with no success (~15 min) the crawl is
  declared banned: `#exhausted?` goes true, `#wait` stops blocking so shutdown is
  immediate, and `fetch` aborts.
- The mutex is never held across a sleep, and wake-ups are jittered so workers
  don't resume in lockstep.

`SafeRealize` sits on top of it and makes the distinction that matters: **a
throttle is not a broken resource.** `Governor::THROTTLE_ERRORS` is the single
list of what counts — `TooManyRequestsError` **and `ForbiddenError`**, because
api.w3.org signals rate limiting with 403 as well as 429 (w3c_api's whole retry
layer is built around that). Blacklisting a 403 would be the same bug as
blacklisting a 429. It retries a rate-limited realize
`THROTTLE_ATTEMPTS` times behind the shared cooldown and records a give-up in
`SafeRealize.throttled` — *never* in `skipped`. An href that a later attempt does
realize is removed from `throttled` again, so a briefly-throttled-then-recovered
resource doesn't count against the budget for a document that is in fact present.
`fetch_specifications_page` is the exception to `THROTTLE_ATTEMPTS`: an index page
retries until the *governor* gives up, since a 3-attempt cap would pre-empt the
escalation ladder and report a pagination fault instead of the real reason.
Everything else is unchanged:
`NotFoundError` and other terminal `Lutaml::Hal::Error`s (403, 5xx) still go into
`skipped` (a `Concurrent::Map`) so a broken link isn't re-fetched for every
reference, and network errors are remembered nowhere so a later reference can try
again. 5xx deliberately stays a permanent skip — the handful of persistent
per-resource 500s a healthy crawl sees are broken records, and routing them
through the governor would open a pool-wide cooldown for each.

Successful objects are cached by **w3c_api** (lutaml-hal caches realized objects
keyed by URL, thread-safely as of lutaml-hal 0.2.1), so `SafeRealize` doesn't
cache them.

> **Why this exists.** The 2026-08-19 `relaton-data-w3c` crawl ran **4 h 56 m**
> (healthy runs take ~1 h 30 m), permanently blacklisted **1,412** rate-limited
> resources, and only then aborted on a failed index page. Every 429 warning in
> that log is ~31 s apart — one exhausted lutaml-hal chain — i.e. *every* request
> for four hours was rate-limited. Had the last index page happened to succeed,
> a dataset missing 1,412 documents would have been committed.

### Index (`index-v2`, pubid-keyed)

`INDEXFILE` is the pubid-backed **`index-v2`**: rows are `Pubid::W3c::Identifier`
leaves serialized as `_type: pubid:w3c:*` with a `number` (the document slug) and
an optional verbatim `date`.

```yaml
- :id:
    _type: pubid:w3c:recommendation
    number: xml-names
    date: '20091208'
  :file: data/rec-xml-names-20091208.yaml
```

**Why.** `Relaton::Index::Type#candidates_by_number` sorts and binary-searches
every row on `id.root.number.to_s`. The old `index-v1` stored plain hashes and
was built without `pubid_class:`, so `FileIO#sorted` stayed false and every
lookup scanned all 17,287 rows. Keyed on the pubid slug the corpus splits into
**1,972 buckets**, the largest holding 101 rows.

**The pubid contract.** `Pubid::W3c::Identifier` keeps the slug in `number`.
It was called `code` until pubid #339 (merged 2026-08-28, `181fd4b9`), which
renamed it with **no alias** — read `number`, never `code`. The root `Gemfile`
pins pubid to `main`, so a checkout whose lock predates that merge still has the
old attribute: run `bundle update pubid`, not `bundle install`, because an
already-locked git source does not refloat.

**Producer, consumer and processor must stay in step.** All three pass
`pubid_class: ::Pubid::W3c::Identifier` — `DataFetcher#index`,
`Bibliography#index` and `Processor#remove_index_file`. On the producer side
`#index_primary` stores the pubid **object**: `Relaton::Index::FileIO#save` only
serializes to the `_type:` shape when the value is an instance of the configured
`pubid_class`, so handing it a hash writes a v1-shaped file under a v2 name,
silently, with no narrowing. On the consumer side, omitting `pubid_class:` leaves
the rows as raw hashes and `FileIO#sorted` false, so `Type#search` stops
narrowing — also silently.

**How a reference is matched.** `Bibliography#best_match` passes the parsed
pubid to `Index::Type#search`, which is what enables the bsearch; a block alone
scans everything. It then follows the ETSI idiom
(`lib/relaton/etsi/bibliography.rb`) — ignore exactly what the reference omitted:

```ruby
ignore = %i[date].select { |attr| pubid.public_send(attr).nil? }
rows = index.search(pubid) { |r| pubid.matches?(r[:id], ignore: ignore) }
```

`date` is W3C's only optional component. The maturity level is **not**
ignorable: it is the identifier's class, and `Pubid::Identifier#matches?`
compares through `exclude` → `self.class.new(...)`, so `WD-`, `REC-` and a bare
slug never match each other — the contract the bespoke `PubId#==` had for its
`stage`/`type`. Newest edition wins, with the file path breaking ties because
undated rows all score 0 and the index sort is not stable.

Two things the narrowing cannot do, both handled around it:

- **Case.** The bsearch key is case-sensitive; `PubId#==` compared its slug with
  `casecmp?`. When the narrowed range is empty, `#loose_match?` repeats the
  comparison case-insensitively over a full scan (the BIPM `search_index`
  precedent).
- **Queries that are not identifiers.** `#parse_ref`/`#normalize_ref` absorb a
  URL (`https://www.w3.org/TR/xml-names/`) and a leading `TR-`/`TR/`, which the
  bespoke regex accepted. A URL is not an identifier and `TR` is a path segment
  of one rather than a maturity level, so neither belongs in a pubid grammar —
  they stay here. The publisher prefix is added when absent. A reference pubid
  still rejects is a **miss, not an error**: `parse_ref` returns nil outside the
  transport rescue, so it never becomes a `Relaton::RequestError`.

**An unparseable id is an ERROR, never a warning.** `Docidentifier#parse` logs at
`Util.error` and leaves `#pubid` nil — it must not raise, or an already-published
record would stop deserializing. `DataFetcher#index_primary` then records the
failure in `@errors` **keyed by the id, not the output path** (the id is the
defect; one broken id reaching several files must still report once), and the
inherited `Core::DataFetcher#report_errors` logs it and raises a tracked GitHub
issue. The row is skipped rather than indexed unparsed: `Relaton::Index` rejects
the *whole* index if one row fails to deserialize, so one bad record must cost
one document, never every lookup. The data file is still written — unindexed,
not lost.

`Core::DataFetcher#report_errors` treats a **String** `@errors` value as the
message itself; a boolean still means "this field failed for every record" and
renders as `Failed to fetch <key>`. That is what lets this flavor report a
specific per-document failure without overriding `report_errors`.

### Key Dependencies

- **relaton-bib** (~> 2.2.0) — provides base `Bib::Item`, `Bib::Ext`, `Bib::Doctype` and serialization mixins (LutaML model layer)
- **relaton-core** — provides base `Core::Processor` and `Core::DataFetcher`
- **relaton-index** — index-based search for bibliographic references; also unpacks the index zip at runtime
- **pubid** — `Pubid::W3c::Identifier` backs `Docidentifier` and the `index-v2` rows
- **w3c_api** (~> 0.3.3) — W3C API (HAL/REST) client used by `DataFetcher` to retrieve specifications; owns the `User-Agent`, the 403 retry, and the object cache. The 0.3.3 floor is load-bearing, not cosmetic — see **Rate limiting & retries**.
- **lutaml-hal** (~> 0.2, >= 0.2.5) — HAL layer beneath w3c_api. Declared directly because this flavor rescues `Lutaml::Hal::*` error classes by name; `ForbiddenError` only exists from 0.2.5, and w3c_api's own `~> 0.2.1` would resolve happily to an older one and NameError at rescue time. 0.2.5 also made `Client#get`'s last-response bookkeeping thread-local (lutaml/lutaml-hal#21), which matters directly to the worker pool.

The W3C data is fetched entirely through `w3c_api`; the older RDF/SPARQL/scraping stack (linkeddata, rdf, sparql, shex, mechanize, …) has been removed.

### Schema Validation

XML output is validated against RelaxNG grammars in `grammars/`:
- `relaton-w3c-compile.rng` — top-level compiled grammar (includes all others)
- `relaton-w3c.rng` — W3C-specific overrides (DocumentType restrictions)
- `basicdoc.rng`, `biblio.rng`, `biblio-standoc.rng` — shared base schemas

Tests use [Jing](https://github.com/jing-trang/jing-trang) for RelaxNG validation.

### Test Structure

Tests use RSpec with:
- **Round-trip tests** — YAML/XML → object → YAML/XML, verifying lossless serialization
- **Schema validation** — XML output validated against `grammars/relaton-w3c-compile.rng`
- **VCR** — recorded HTTP cassettes in `spec/vcr_cassettes/` (7-day re-record interval)
- **WebMock** — disables external HTTP in tests

Test fixtures live in `spec/fixtures/` (YAML and XML files).

## Style

- Follows [Ribose OSS Ruby style guide](https://github.com/riboseinc/oss-guides) via RuboCop
- Target Ruby version: 3.1
- RuboCop config inherits from remote Ribose guide; Rails cops disabled

## CI

GitHub Actions workflows (auto-generated by Cimas) delegate to shared workflows in `relaton/support`:
- `rake.yml` — runs tests on push to main and PRs
- `release.yml` — gem versioning and publishing to RubyGems

## Testing

- **Index fixture:** `spec/fixtures/index-v2.zip` — the published index verbatim, seeded into the `Relaton::Index` pool by `spec/support/webmock.rb`. Refresh it from the live published `index-v2.zip`; there is no `rake spec:update_index` task in this repo.
  - It is built **with `pubid_class:`**. Without it the rows stay raw hashes and `Type#search` silently stops narrowing, so the suite would pass while exercising something the runtime never does.
  - It is re-seeded in **`before(:each)`**, not only `before(:suite)`: `Index::Pool#type` replaces the pooled entry whenever `actual?` says no, and `DataFetcher#index` asks for the same `:W3C` type with `file:` but no `url:`. `before(:suite)` alone leaves a later example searching a producer index. IANA hit this first.
  - The zip name is read from `Relaton::W3c::INDEXFILE`, but **lazily** — `spec_helper` loads `support/` before the flavor, so touching the constant at file-body time NameErrors.
