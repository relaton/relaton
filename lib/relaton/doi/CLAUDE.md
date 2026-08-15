# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

relaton-doi is a Ruby gem that fetches bibliographic metadata via DOI identifiers from the Crossref API and converts them into Relaton bibliographic objects. It detects DOI patterns to produce flavor-specific items (NIST, IETF, BIPM, IEEE) or generic `Bib::ItemData`.

## Common Commands

```bash
bundle exec rake spec          # Run all tests (default rake task)
bundle exec rspec spec/relaton/doi/parser_spec.rb  # Run a single spec file
bundle exec rspec spec/relaton/doi/parser_spec.rb:224  # Run a single example by line
rubocop                        # Lint
rubocop -a                     # Lint with auto-correct
```

## Architecture

**Namespace:** `Relaton::Doi` (migrated from legacy `RelatonDoi`).

**Core flow:** `Crossref.get(doi)` → HTTP fetch from api.crossref.org → `Parser.parse(json_hash)` → flavor-specific `ItemData`

Key classes in `lib/relaton/doi/`:

- **`Crossref`** — module with `get(doi)` and `get_by_id(id)`. Uses **Mechanize** (`Mechanize.new` with a custom `USER_AGENT`). `get_by_id` retries twice, backing off by `x-rate-limit-interval * n`, then raises `Relaton::RequestError`; only a 404 returns nil.
- **`Parser`** — largest file (~827 lines). Converts Crossref JSON hashes to Relaton objects. Factory method `parse(src)` delegates to `create_bibitem` which picks the right ItemData class based on DOI pattern (`/nist/` → `Nist::ItemData`, `/rfc\d+/` → `Ietf::ItemData`, etc.). Contains ~30 `parse_*` helper methods for individual bibliographic fields.
- **`Processor`** — `Relaton::Processor` subclass for the Relaton registry system. Entry point for `get`, `from_xml`, `hash_to_bib`.
- **`Util`** — logging utility, extends `Relaton::Bib::Util` with `PROGNAME = "relaton-doi"`.

## Test Setup

- **RSpec** with `expect` syntax only (monkey patching disabled)
- **VCR** cassettes in `spec/vcr_cassettes/` record Crossref HTTP responses, re-recorded every 7 days on purpose (see root `CLAUDE.md`). Because Crossref rate-limits, **re-record this suite alone** — under parallel `rake spec` it answers 429 and the empty body gets recorded as if it were data.
- **XML fixtures** in `spec/fixtures/` — expected output XML files. The `read_fixture` helper auto-substitutes today's date into `<fetched>` tags.
- **equivalent-xml** gem for XML comparison in integration tests
- Integration tests in `spec/relaton/doi_spec.rb` cover 40+ document types via VCR cassettes
- Unit tests in `spec/relaton/doi/parser_spec.rb` test Parser methods directly with hash inputs

## Rate limiting

Crossref advertises `X-Rate-Limit-Limit: 10` / `X-Rate-Limit-Interval: 1s` and
`X-Concurrency-Limit: 3`. Both request paths honour that and **fail loud rather
than degrade**:

- `Parser#fetch_crossref` handles `429` *before* its generic 4xx→nil return,
  sleeping `retry_delay * attempt` (`Retry-After`, else `X-Rate-Limit-Interval`,
  else a 1s floor) with the **sleep itself** clamped to `MAX_RETRY_DELAY`, for up
  to `MAX_RETRIES` attempts, then raising `Relaton::RequestError`. Only the
  numeric form of `Retry-After` is used — RFC 9110 also permits an HTTP-date, and
  scanning digits out of a date would yield the day-of-month.
- `Crossref.get_by_id` retries twice with `Crossref.backoff`, then raises; only a
  404 returns nil.

Both apply a **1-second floor**, because a throttled response may carry no
rate-limit headers at all (the 429s observed here had only
`Date`/`Content-Length`/`Connection`). Treating a missing header as `0` would
retry with no delay — hammering the endpoint that just asked us to slow down.

**A throttle must never collapse into "not found."** `fetch_crossref`'s callers
(`#parent_item`, `#fetch_location`) read nil as "this record has no parent /
no location", so a 429 returning nil silently produced an *incomplete* item —
e.g. a book chapter with none of its editors — instead of an error. That is also
how 429s ended up baked into cassettes as if they were data; see the cassette
notes in the root `CLAUDE.md`.

## Key Constants in Parser

- `TYPES` — maps 23 Crossref document types to Relaton types (e.g., `"book-chapter"` → `"inbook"`)
- `REALATION_TYPES` — maps 37 Crossref relation types to Relaton relation types
- `COUNTRIES` — `%w[USA]`, used by `parse_place` to distinguish country vs region
