# CLAUDE.md

## Development

- `bundle install` — install dependencies
- `bundle exec rake spec:calconnect` — run this flavor's suite
- `bundle exec rubocop` — lint

The root `Gemfile` git-pins pubid. Pick it up with **`bundle update pubid`**,
never `bundle install` — an already-locked git source does not refloat.

## Index

### The gem builds and reads `index-v2`; the data repo owns `index-v1`

`INDEXFILE` is the pubid-backed `index-v2`: rows are
`Pubid::Calconnect::Identifier` hashes
(`_type: pubid:calconnect:standard`, with `series`/`number`/`year`, plus
`month`/`day` for the one fully dated row). All three index call sites —
`DataFetcher#index`, `HitCollection#index` and `Processor#remove_index_file` —
pass `pubid_class: ::Pubid::Calconnect::Identifier`. Omitting it on the
**producer** writes v1-shaped rows under a v2 name, silently (`FileIO#save`
calls `to_hash` only for instances of `pubid_class`); omitting it on the
**consumer** leaves the rows raw hashes with `FileIO#sorted` false, so every
lookup scans all 191 rows.

**`index-v1` is not this gem's concern at all.** It exists only for released
relaton **v2** clients, and `relaton-data-calconnect` owns it end to end:
`build_index_v1.rb` rebuilds it there from each crawled document's own primary
`docidentifier` string out of `data/` — unlike relaton-data-{ecma,w3c,iana,bipm},
it does **not** derive it from the v2 rows. CalConnect can do that and they
cannot, because a v1 row id is simply the document's printed id, with no edition
or volume to split back out. The upshot for this side is that their v1 never
depends on pubid, so nothing here can break it and there is no v1 fixture and no
v1 assertion in this suite.

### Lookup

`HitCollection#search_index` follows the ETSI/W3C/ECMA idiom:

- **Pass the pubid, not the string.** `Type#search_candidates` narrows only when
  the argument is not a `String`, and a block alone never narrows — so the plain
  string this flavor used to pass disabled the binary search however the index
  was built. `pubid_class:` alone fixes nothing; both had to change together.
- **Ignore what the reference omits.** The date is the only ignorable
  component. `series` is never ignorable — it is what keeps `CC/CD 51016` and
  `CC/WD 51016` apart — and neither is its *absence*, so `CC 36010` does not
  match `CC/WD 36010`. `matches?` compares the identifier's class and every
  non-ignored attribute.
- **An unparseable reference finds nothing**, with a warning, and is a miss
  rather than an error — it must never surface as a `Relaton::RequestError`.

**This ended a silently ambiguous substring scan.** The old string search
matched any row *containing* the reference: `CC/DIR 1000` answered with all five
`CC/DIR 1000x` documents and `CC/A 1` with every `CC/A 1xxx`. A number now
matches exactly, and a leading zero is significant (`CC/A 0001` is not
`CC/A 1`).

**Ordering is newest-first, and it has to be explicit.** The index is sorted by
number, so rows sharing a number arrive in no meaningful order; without
`#recency_key` a bare `CC/S 0601` would answer with an arbitrary one of the 2005
and 2006 documents. Date segments are compared as integers and negated for
descending order, with `row[:file]` breaking ties because the index sort is not
stable.

`Bibliography.get` no longer regex-splits the reference before searching: pubid
parses `CC/DIR 10005:2019` whole, so a dated reference narrows in the index
itself. The `year` **argument** still needs filtering afterwards, because an
undated reference reaches every year of the document — that is why
`bib_results_filter` stays, and why it now reads the year off `row[:id].date`
instead of scraping a rendered string (the old `/:(\d{4})$/` would raise
`TypeError` against a pubid).

### Why this flavor needs no render flags

CalConnect is the simple end of the pubid migrations, and the reason is worth
stating so nobody adds machinery it does not need. `Pubid::Calconnect` renders
the publisher by default and models no edition and no volume, so the index key
and the document's own printed id are **the same string**: `CC/DIR 10005:2019`
in the row, `CC/DIR 10005:2019` in the record. There is nothing to opt in to
(contrast `Relaton::ThreeGpp::Docidentifier`, which must pass
`with_publisher: true`) and nothing to opt out of (contrast
`Relaton::Ecma::Docidentifier`, which must suppress the edition and the volume).
`DataFetcher#index_id` therefore returns the docidentifier's pubid untouched —
no `dup`, no mutation.

The number is a plain `String`, not a `Components::Code`, and deliberately so:
it preserves leading zeros (`0001`, `0514`) and keeps a sub-number in one token
(`0812-1`, `0707.1`). CalConnect models **no part** — those are numbers, not a
number plus a part — which is why `Docidentifier#remove_part!` and
`#to_all_parts!` are no-ops. Do not "fix" them by splitting the number.

`Docidentifier` follows the IHO/W3C shape: `content=` calls `super` first, so
`content` stays the source string verbatim. That is load-bearing beyond
convention — `ItemData#create_id` derives the record's `id` from
`content.gsub(/\W+/, "")`, so a re-render would move every published id.
`#remove_date!` is the one real mutator (`CC/DIR 10005:2019` ->
`CC/DIR 10005`); it writes back through `store_content`, never `content=`,
because a re-parse would rebuild `@pubid` and discard the mutation.

### An unparseable docid is recorded, not just warned

`Docidentifier#parse` logs at `Util.error` and leaves `#pubid` nil — it must not
raise, or an already-published record would stop deserializing.
`DataFetcher#add_to_index` then records
`@errors[docid] = "Unparseable primary id … was not indexed (…)"`, which the
inherited `Core::DataFetcher#report_errors` logs and `Logger::Channels::GhIssue`
turns into a GitHub issue at the end of the crawl. (`report_errors` treats a
**String** value as the message; the boolean form the parsers use means "this
field failed for every record" and is the wrong shape here.)

The row is skipped rather than indexed unparsed, because `Relaton::Index`
rejects the **whole** index if one row fails to deserialize and its sort calls
`.root.number` on every id. `#write_doc` writes the file **before** indexing, so
the document is unindexed, never lost.

### Measured against the live published corpus

All 191 rows of the published index (2026-09-08): every id parses; `to_s`
reproduces the published string **exactly**; `from_hash(to_hash)` round-trips
all 191; they render **191 distinct keys**, so nothing collapses under
`add_or_update`; `root.number` is empty for none. Driving all 191 documents of
`relaton-data-calconnect`'s `data/` through `write_doc` produces 191 rows with 0
errors and reads back as 191 identifiers with `FileIO#sorted` true.
`spec/calconnect/relaton/calconnect/pubid_contract_spec.rb` pins these
properties offline against the committed `index-v2` fixture.

No pubid change was needed for this migration. `Pubid::Calconnect` was written
for it.

## Testing

- **Framework:** RSpec with VCR cassettes and WebMock.
- **Index fixture:** `spec/calconnect/fixtures/index-v2.zip` — the whole
  published index (191 rows), copied verbatim, so the stored shapes are exactly
  what the runtime deserializes. Refresh it with
  `bundle exec rake spec:update_index_calconnect`
  (`tasks/index_fixture_calconnect.rb`); `#build` refuses a source that is not a
  pubid index-v2 rather than writing a fixture `Relaton::Index` would reject
  wholesale.
- It is seeded into the `Relaton::Index` pool by
  `spec/calconnect/support/webmock.rb`, built **with `pubid_class:`** — without
  which the rows stay raw hashes, `FileIO#sorted` stays false, and
  `Type#search` silently stops narrowing, so the suite would pass while
  exercising something the runtime never does. It is written to a temp file and
  read through `FileIO`, not stuffed into `@index` directly, because the
  deserialize and the sort both happen on that read path.
- There is **no `index-v1` fixture**, deliberately: `index-v1` is a released
  relaton v2 artifact that this gem neither produces nor reads (see the index
  section). Don't reintroduce one.
- **The `before(:each)` re-seed is not belt-and-braces.** `Index::Pool#type`
  replaces the pooled entry whenever `actual?` says no, and `DataFetcher#index`
  asks for the same `:CC` slot with a *different* file (`index-v2.yaml`). With a
  `before(:suite)` seed alone the fetcher evicts the fixture, and every later
  example goes to the network for real — which is exactly how six examples used
  to die with `Errno::EPERM` on `~/.relaton/cc/index-v1.yaml`. The pool key is
  `type.upcase.to_sym`, so the producer and the consumer share one slot.
  (The ECMA/OGC pattern.)
- **VCR cassettes:** `spec/calconnect/vcr_cassettes/` — index downloads are
  ignored by VCR, matched on the constant so a version bump cannot leave the
  filter naming the old file and let a real download through.
- `pubid_contract_spec.rb` checks the whole fixture corpus for the properties
  the index key depends on: every row deserializes, one distinct rendered key
  per row, no empty bsearch key, a `to_hash`/`from_hash` round trip, and every
  rendered key parsing back to the same identifier. Re-run it whenever the
  fixture is refreshed.
- `hit_collection_spec.rb` covers the runtime search path — narrowing,
  ordering, and the misses. It was an empty `describe` block before this
  migration, so the lookup had no direct coverage at all.
- The `bibdata`/`bibitem` round-trip examples and two `gets` examples validate
  XML with Jing, which needs a **JVM on PATH**. Without one they fail with
  `Jing::ExecutionError`, which is environmental, not a code defect — check
  `java -version` before chasing it.
