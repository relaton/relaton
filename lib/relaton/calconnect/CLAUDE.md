# CLAUDE.md

## Development

- `bundle install` — install dependencies
- `bundle exec rake spec:calconnect` — run this flavor's suite
- `bundle exec rubocop` — lint

The root `Gemfile` git-pins pubid. Pick it up with **`bundle update pubid`**,
never `bundle install` — an already-locked git source does not refloat.

## Index

### The gem builds `index-v2`; it still reads `index-v1`

`INDEXFILE` is the pubid-backed `index-v2`: rows are
`Pubid::Calconnect::Identifier` hashes
(`_type: pubid:calconnect:standard`, with `series`/`number`/`year`, plus
`month`/`day` for the one fully dated row). `DataFetcher#index` passes
`pubid_class: ::Pubid::Calconnect::Identifier`. Omitting it on the producer
writes v1-shaped rows under a v2 name, **silently** — `FileIO#save` calls
`to_hash` only for instances of `pubid_class` — and the consumer then rejects
the whole index.

`INDEXFILE_V1` is a **temporary read-side name**, not a second published index.
`relaton-data-calconnect` publishes no `index-v2.zip` yet, so `HitCollection`
and `Processor#remove_index_file` still read the legacy v1. When the data repo
publishes, the consumer commit points both at `INDEXFILE`, adds `pubid_class:`
to both, and deletes `INDEXFILE_V1`.

This gem no longer produces `index-v1`. `relaton-data-calconnect`'s crawler
derives it from the v2 rows — the ECMA/IANA/BIPM/W3C shape.

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

All 188 rows of `relaton-data-calconnect`'s `index-v1.yaml`: every id parses;
`to_s` reproduces the published string **exactly**; `from_hash(to_hash)`
round-trips all 188; they render **188 distinct keys**, so nothing collapses
under `add_or_update`; `root.number` is empty for none. Driving all 188
documents through `write_doc` produces 188 rows with 0 errors, reads back as 188
identifiers with `FileIO#sorted` true, and `id.to_s` reproduces the published v1
id set exactly — which is what the data repo's derivation depends on.
`spec/calconnect/relaton/calconnect/pubid_contract_spec.rb` pins these
properties offline against the committed fixture.

No pubid change was needed for this migration. `Pubid::Calconnect` was written
for it.

## Testing

- **Framework:** RSpec with VCR cassettes and WebMock.
- **Index fixture:** `spec/calconnect/fixtures/index-v1.zip`, seeded into the
  `Relaton::Index` pool by `spec/calconnect/support/webmock.rb`. It is still the
  v1 index because the runtime still reads v1; the consumer commit replaces it
  with a verbatim cut of the published `index-v2.zip` and builds the `Type` with
  `pubid_class:` — without which the rows stay raw hashes, `FileIO#sorted` stays
  false, and `Type#search` silently stops narrowing, so the suite would pass
  while exercising something the runtime never does.
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
  the index key depends on: every id parses, one distinct rendered key per row,
  no empty bsearch key, a `to_hash`/`from_hash` round trip, and `to_s` back to
  the published string. Re-run it whenever the fixture is refreshed.
- The `bibdata`/`bibitem` round-trip examples and two `gets` examples validate
  XML with Jing, which needs a **JVM on PATH**. Without one they fail with
  `Jing::ExecutionError`, which is environmental, not a code defect — check
  `java -version` before chasing it.
