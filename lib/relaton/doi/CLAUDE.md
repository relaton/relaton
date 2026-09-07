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

## Crossref markup

Crossref returns abstracts and titles as JATS, and it sometimes encodes that markup as HTML
entities. `Parser#normalize_markup` decodes the entities; `create_title`, `parse_abstract`,
`parse_series`, `included_in_relation` and `create_org` all route through it, so an
affiliation name no longer goes out double escaped (`AT&amp;T` instead of `AT&T`).

**It decodes only content that holds no markup of its own** (`TAG_RE`), and it passes `nil`
through. Crossref escapes an ampersand and a literal angle bracket *inside* real markup, so
an unconditional decode — which is what upstream relaton-doi#26 does — turns
`<jats:p>Smith &amp; Jones</jats:p>` into markup that no longer parses. The sanitizer then
gives up on it and an unescapable string reaches the output: metanorma-pdfa#99 again, on the
far more common input. A `nil` reaches `create_org` from a funder entry carrying only a DOI
and from an affiliation carrying only a ROR id, and `CGI.unescapeHTML(nil)` raises
`TypeError`, which aborted the whole fetch.

The JATS also carries a `jats:` prefix on the elements and sometimes an `xlink:` prefix on an
attribute, which Relaton never declares. **Removing those prefixes is not this flavor's job**
— `Relaton::Bib::Sanitizer` runs on every `Bib::Title` and `Bib::Abstract` assignment and
declares each undeclared prefix so the markup parses and maps to the basicdoc set. Upstream
relaton-doi (relaton-doi#26) carries its own `drop_namespaces` only because that sanitizer fix
is not in a released relaton-bib; here both ship in one gem, so this flavor keeps the entity
decode alone. Do not add a second prefix-stripping layer. The unit specs in
`spec/doi/relaton/doi/parser_spec.rb` pin the behaviour, not the layer, so they hold either way.

`spec/doi/relaton/doi_spec.rb`'s shared `"fetch document"` example asserts
`Nokogiri::XML(xml).errors` is empty. That is the property relaton-render requires
(metanorma-pdfa#99), and it guards every integration example.
