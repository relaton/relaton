# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-cen retrieves European Committee for Standardization (CEN/CENELEC) bibliographic data using the Relaton model. It has no API or curated index — it **scrapes** the CEN/CENELEC public portal (`standards.cencenelec.eu`) with Mechanize, simulating the search form and parsing HTML tables for title, status, ICS codes, publication dates, and committee info. Uses `Relaton::Bib::ItemData` directly (no relaton-iso dependency).

## Development

```bash
bundle exec rake spec:cen                       # the CEN suite
cd spec/cen && bundle exec rspec -I . relaton/cen/docidentifier_spec.rb
```

(No gem-local rubocop config; the monorepo root config applies.)

## Architecture

Namespace: `Relaton::Cen`. Reference handling is **entirely `Pubid::CenCenelec`**
— there is no hand-rolled identifier regex left. Because CEN publishes **no
index** and has no data repo, this is the **BSI shape**, not the index-v2 shape:
parse the query with pubid, select the portal hits with pubid, back the
`Docidentifier` with pubid. There is no `INDEXFILE` and no `pubid_class:`.
**Don't add an index.**

Retrieval flow:

1. **Bibliography** (`lib/relaton/cen/bibliography.rb`) — `get(code, year, opts)`
   and `search` entry points. `parse` wraps
   `Pubid::CenCenelec::Identifier.parse` and **raises** on an unrecognized query
   (the root `CLAUDE.md` rule "An unrecognized query reference raises"); only the
   data side rescues, in `Hit#pubid`. `get` keeps an early `nil` for an **empty**
   reference — an empty string is no reference, not a malformed one — and
   otherwise lets `Pubid::Errors::ParseError` propagate. `search` keeps its
   `rescue Mechanize::ResponseCodeError, Net::ReadTimeout` by name; don't widen
   it to `StandardError`, which would swallow the parse error and turn a
   transport failure into a class `Relaton::Db#net_retry` does not retry.
2. **HitCollection** (`lib/relaton/cen/hit_collection.rb`, extends
   `Relaton::Core::HitCollection`) — the web flow: GET the portal, follow the
   redirect, submit the search form (`STAND_REF`) via Mechanize, parse the result
   table, then `sort` by a pubid-derived key.
3. **Hit** (`lib/relaton/cen/hit.rb`, extends `Relaton::Core::Hit`) — `item`
   lazy-loads the detail page via the scraper; `pubid` memoizes the hit code
   parsed with pubid and is **nil** when the grammar cannot read it, because the
   portal lists draft revisions such as `prEN 13306 rev` and one such row must
   not abort the search. The filter, the sort and the scraper all read it, which
   is why it is memoized (the `Relaton::Bsi::Hit#pubid` idiom).
4. **Scraper** (`lib/relaton/cen/scraper.rb`) — Mechanize/XPath HTML parser.
   Maps CEN date abbreviations (DOR→adapted, DAV→issued, DOA→announced,
   DOP→published, DOW→obsoleted) and relation headers (supersedes→obsoletes,
   normative reference→cites); a small `COMMITTEES` map resolves codes like
   TC 459→ECISS. `fetch_structuredid` takes the docnumber and partnumber from
   the pubid. Two regexes remain here and are **not** identifiers, so they stay:
   the committee regex in `fetch_contributors` and the year-of-a-date-string
   match in `fetch_copyright`.
5. **ItemData / Model::Item** (`item_data.rb`, `model/`) —
   `Relaton::Cen::ItemData` extends `Relaton::Bib::ItemData`; `Ext` adds a
   `StructuredIdentifier` (docnumber/partnumber, agency "CEN").
6. **Processor** (`lib/relaton/cen/processor.rb`) — registry integration. Sets
   `@pubid_flavor = :CenCenelec`, so `Core::Processor#prefixes` reads
   `Pubid::CenCenelec.prefixes` (`EN CEN CLC CWA HD ES CR ENV`) into the global
   prefix register; every one of the eight resolves to `[Relaton::Cen]` alone.
   `@defaultprefix` is deliberately **narrower** than that list — widening it to
   `ES` would claim a very generic token for this flavor.
   It lazy-`require_relative`s `../cen` inside each method, like every other
   flavor: the require used to sit at file load, so merely building a `Db`
   pulled in mechanize, isoics and pubid. `spec/relaton/lazy_loading_spec.rb`
   guards that.

### `#root` is the accessor that answers for every form

An `AdoptedEuropeanNorm` (`CEN ISO/TS 21003-7:2019`) carries **no** number, part
or year of its own — they live on the adopted ISO identifier — so
`base_document.year` is nil for it while `root.year` is `"2019"`. Measured over
the 67-reference probe corpus, `root.year` equals the old first-year regex on
**every** parseable reference and `base_document.year` misses all three
adopted-norm forms. So the year, number and part are read from `#root`; only the
**family** grouping is read from `#base_document`, which keeps
`EN ISO 1234` and `CEN ISO/TS 1234` apart.

### `Docidentifier` — the year rule

`Relaton::Cen::Docidentifier` (`model/docidentifier.rb`, `< Bib::Docidentifier`)
parses its `content` into `@pubid` while the lutaml `content` attribute stays a
plain string for serialization. The parse is on the **data side**: it lazily
`require "pubid"` and rescues `LoadError`/`StandardError`, so a non-CEN value (an
ISBN) or a code the grammar rejects stays verbatim with `@pubid` nil, and all
three mutators no-op. `Pubid#exclude` returns a **copy** (the BSI shape, not
IALA's in-place setters), so each mutator replaces `@pubid` and re-renders
through the aliased `store_content` — writing through `content=` would re-parse
and discard the mutation.

**`remove_date!` drops the LAST year, and only that one.** On a supplement the
identifier names the supplement, so its own year is the last one:
`EN 13250:2000/A1:2005` is amendment A1 of 2005, and the `2000` belongs to the
base document it amends — excluding that would strip the base document's
identity rather than a date. So the rule is `exclude(:supplement_year)` when
there is a supplement year, else `exclude(:year)`:

| input | `remove_date!` |
|---|---|
| `EN 13306:2017` | `EN 13306` |
| `EN 13250:2000/A1:2005` | `EN 13250:2000/A1` |
| `EN 285:2015+A1:2021` | `EN 285:2015+A1` |
| `EN 61375-2-3:2015/AC:2016-11` | `EN 61375-2-3:2015/AC` |
| `EN 285:2015+A1` | `EN 285+A1` |

The last two rows are where this beats the old `content.sub!(/:\d{4}$/, "")`:
neither string ends in a bare year, so the regex stripped **nothing** and
`to_most_recent_reference` returned a dated reference. `:supplement_year` is a
CEN-only key, and it resets the supplement's year and month together. Note that
ISO and IEC are different — there `exclude(:year)` removes *every* year.

`remove_part!` is `exclude(:part, :subpart)`, and `to_all_parts!` is both plus
the `all_parts` flag. **`Pubid::CenCenelec::Renderer` never reads
`all_parts`**, so the flag is invisible in `content` — setting it on `EN 1325`
renders `EN 1325` either way — and `to_all_parts!` degrades to a rendered
part-and-date strip while the flag is set structurally, for anything that later
reads the pubid rather than the string. BSI and IALA make the same trade-off,
for the same reason. pubid holds a sub-part **inside** `part` (`61375-2-3`
gives `"2-3"`), which is also why `fetch_structuredid` swaps the separator to
reproduce the old `"2:3"` partnumber.

### Hit selection — what the query left unsaid

`search_filter` sends the caller's **raw reference text** to the portal form —
that is search-engine input, not identifier parsing (the BSI precedent) — and
selects with `query.matches?(hit.pubid, ignore: …)`. One idiom decides what to
ignore, and it needs no per-class accessor: **a component is absent from a
reference when excluding it changes nothing.**

```ruby
def absent?(id, *keys) = id.exclude(*keys) == id
def supplement?(id)    = id.base_document != id
```

That works for the forms that hold the component on a nested identifier, where a
direct accessor returns nil (`CEN ISO/TS 21003-7` keeps its part on the adopted
ISO document, yet `absent?(id, :part, :subpart)` is correctly false). The list
keeps the rules the old comparison had:

- no part → ignore `:part, :subpart`
- no base year → ignore `:year`
- a supplement that carries **no year** → ignore `:supplement_year`

The third condition's `supplement?` half is **belt and braces, kept on purpose.**
pubid's `matches?` is `exclude(*ignore) == other.exclude(*ignore)`, and its `==`
is **class-strict** (`Lutaml::Model::ComparableModel#same_class?` uses
`instance_of?`), so a base-document class can never equal a supplement wrapper
however long the ignore list grows: measured on pubid `b4d52e5d6`,
`CEN ISO/TS 21003-7` does not match `CEN ISO/TS 21003-7:2008/A1:2010` even with
`:supplement_year` ignored. Don't read the guard as load-bearing today — but
don't delete it either. That class-strictness is pubid's internal invariant,
not a documented contract, while "a base reference must never answer with its
own amendment's record" is **this flavor's** rule, which the old code stated
explicitly by requiring amendment identity. The guard keeps the rule in the
flavor rather than inherited by luck, and
`spec/cen/relaton/cen/bibliography_spec.rb` covers it (`never selects a
supplement for a base reference`), so a pubid that relaxed `==` would fail
loudly here instead of quietly returning an amendment.

So `:supplement_year` is ignored only when the query itself names a supplement
without a year: `EN 285:2015+A1` → `EN 285:2015+A1:2021`, but never
→ `EN 285:2015`.

Two selections got **stricter**, and both were latent bugs in the regex:
`code_to_parts` required a literal `+` for its `amd` group and never compared its
`ac` group at all, so a `/A1:2005` amendment was invisible to it — a query for
`EN 13250:2000` matched the amendment record, and `HD 1215-2:1988` kept its
corrigendum hit and was saved only by the sort order. pubid rejects both.

### Sort order

`HitCollection#sort` is a memoized `sort_by!` over
`[family, part_segments, -year, supplement_key]`, which reproduces the order the
six `code_to_parts` fields gave: the document family ascending
(`base_document.exclude(:year, :part, :subpart)`), then the part ascending with
a part-less hit **first**, then the year **descending** with a year-less hit
last, then the supplement, so a base document precedes its own amendments and
corrigenda. Part segments are compared as **integers**, so `-10` sorts after
`-2`. An unparseable hit sorts last. The order is load-bearing:
`isobib_results_filter` takes the first hit that matches the year and has an
item, so `EN 13306` answers with the 2017 record and `EN 1325` with the
part-less one.

A consolidated identifier (`EN 285:2015+A1:2021`) holds its base document and
its supplements in `#identifiers` and answers **none** of the
`supplement_type`/`supplement_number`/`supplement_year` accessors itself, so
`supplements` reads `identifiers.drop(1)` for it and `[id]` for a plain
amendment or corrigendum.

## External dependencies

`mechanize ~> 2.10`, `isoics ~> 0.1` (ICS descriptions), `pubid`,
`relaton-core`, `relaton-bib`.

## Testing

RSpec with WebMock + VCR (cassettes in `spec/vcr_cassettes/`, record `:once`, 7-day re-record). Network is blocked via WebMock. No index fixture — CEN is scraped, not indexed; `spec/fixtures/` holds XML/YAML round-trip data. The scraper is inherently brittle to portal HTML changes.

- `spec/cen/relaton/cen/docidentifier_spec.rb` unit-tests the three mutators over
  every identifier form the portal serves, including the two rows above that the
  old regex left unchanged.
- `spec/cen/relaton/cen/bibliography_spec.rb` unit-tests hit **selection** with
  **no HTTP at all**: the ignore-list table and `matches?` are the whole of
  `search_filter`'s decision, and driving them directly covers pairs no cassette
  can. That matters here — the cassettes hold a detail page only for the
  document their own example fetched, so an example that selects a *different*
  hit from the same search (say the 2008 record in `cen_iso_ts_21003_7`) dies
  with `VCR::Errors::UnhandledHTTPRequestError`, not an assertion failure.
- Every `docidentifier[0].content` expectation in `spec/cen/relaton/cen_spec.rb`
  is **unedited** by the pubid migration: what the flavor returns did not change.
- `returns nil when document doesn't exist` is split in two, because
  `CEN NOT FOUND` is not an identifier and now raises. One example asserts
  `Pubid::Errors::ParseError` and makes no request; the other keeps the
  not-found coverage with a parseable reference.
- **Trap:** `gets code` writes `spec/cen/fixtures/bibdata.xml` through
  `write_file`, which writes only when the file is **missing**
  (`spec/spec_helper.rb`). A deleted fixture is silently recreated from whatever
  the current cassette says, and the example then always passes. Never delete it
  to make a spec green; delete it only to regenerate deliberately, then read the
  diff.
