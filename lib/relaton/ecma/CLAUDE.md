# CLAUDE.md

## Development

- `bundle install` — install dependencies
- `bundle exec rake spec:ecma` — run this flavor's suite (from the repo root)
- The ECMA flavor needs pubid support that is not in the released
  `2.0.0.pre.alpha.8`, so the root `Gemfile` git-pins pubid. Pick it up with
  **`bundle update pubid`**, never `bundle install` — see the
  stale-pubid-lock trap in the root `CLAUDE.md`.

## Pubid-backed docidentifier

`Relaton::Ecma::Docidentifier` parses its `content` into a
`Pubid::Ecma::Identifier` kept in `@pubid`, while the lutaml `content` attribute
stays a plain **string** for serialization. Parsing is **soft**: `content=`
lazily requires pubid and rescues `LoadError`/`StandardError`, so a missing gem
or non-ECMA content leaves `@pubid` nil rather than raising. All three mutators
therefore no-op safely, and `Bib::ItemData`'s `#to_all_parts` /
`#to_most_recent_reference` never raise on ECMA items.

**The one ECMA-specific rule — `refresh_content!` renders**
**`to_s(with_edition: false, with_volume: false)`.**

`Pubid::Ecma::Identifier#to_s` renders the edition and the volume **by default**
(`"ECMA-269 ed3 vol2"`). That default is deliberate on the pubid side, because
the index keys on a bare `to_s` — see below. A **document's own** docidentifier
is the opposite: every `ECMA-269` volume file in `relaton-data-ecma` carries
`docidentifier: ECMA-269` and the same title, so the edition and the volume are
index metadata, not part of the printed id. Without the opt-out, any mutation
would silently promote the stored content to the index form.

This is the mirror image of `Relaton::ThreeGpp::Docidentifier`, whose
`refresh_content!` must pass `with_publisher: true` because *its* pubid defaults
to the index rendering and *its* stored content is the fuller one. The two look
contradictory only until you notice each re-renders what its own `content`
already holds.

Component mapping:

- **`remove_date!` → clears `edition`.** ECMA has no date component; `edition`
  is its version discriminator. It is invisible in the rendered bare form, but
  the identifier really does change and a consumer reading `#pubid` sees it.
- **`remove_part!` → clears `part`/`subpart`.** Real here: `ECMA-418-1` →
  `ECMA-418`.
- **`to_all_parts!` → both, plus `all_parts`** behind a `respond_to?` guard; the
  ECMA renderer emits no marker for the flag.

## Index

### The gem builds and reads `index-v2`; the data repo derives `index-v1`

`INDEXFILE` is the pubid-backed `index-v2`: rows are `Pubid::Ecma::Identifier`
hashes (`_type: pubid:ecma:{standard,technical-report,memento}` with
`number`/`part`/`edition`/`volume`). All three index call sites —
`Bibliography#index`, `DataFetcher#index`, `Processor#remove_index_file` — pass
`pubid_class: ::Pubid::Ecma::Identifier`. Omitting it on the **producer** writes
v1-shaped rows under a v2 name, silently (`FileIO#save` calls `to_hash` only for
instances of `pubid_class`); omitting it on the **consumer** leaves the rows raw
hashes with `FileIO#sorted` false, so every lookup scans all 804.

This gem no longer produces the legacy `index-v1`. `relaton-data-ecma`'s
`crawler.rb` derives it from the v2 rows, the IANA/BIPM/W3C shape.

**Why the edition must be in the key.** `Index::Type#add_or_update` keys on a
**bare** `id.to_s`, and 740 of the 804 published rows carry an edition. Before
pubid rendered it, those 804 rows collapsed onto 421 keys — `ECMA-74` 22 rows to
1, `ECMA-262` 18 to 1 — so a crawl would drop **383 of 804 rows and report
success**. Four rows also need `volume`: `ECMA-269` edition 3, volumes 1-4 share
one docidentifier *and* one title, so the volume is the only thing that tells
them apart.

**`#index_id` builds the identifier from the MODEL, not from a rendered string.**
It takes the docidentifier's own pubid, **duplicates** it, then sets `edition`
from `bib.edition.content` and `volume` from the extent locality — the same
three fields `#filename_id` reads. The `dup` is load-bearing: those two are
index metadata, so setting them on the shared object would promote the
document's own printed id to the index form. Filenames are unaffected either
way; `output_file` is fed by `#filename_id`, giving `ecma-269-3-1.yaml`.

**An unparseable docid is recorded, not just warned.** `#add_to_index` writes
`@errors[docid] = "Unparseable primary id … was not indexed (…)"`, which the
inherited `report_errors` logs and `Logger::Channels::GhIssue` turns into a
GitHub issue at the end of the crawl. (`Core::DataFetcher#report_errors` treats
a **String** value as the message; the `@errors[:key] &&= …` boolean form the
parsers use means "this field failed for every record" and is the wrong shape
here.) The row is skipped rather than indexed unparsed, because
`Relaton::Index` rejects the **whole** index if one row fails to deserialize and
its sort calls `.root.number` on every id. The data file is still written, so
the document is unindexed, never lost. (The 3GPP/W3C precedent.)

Verified against the live published corpus: all 804 rows build an identifier,
they render **804 distinct keys** (not 421), `root.number` is empty for none,
`from_hash(to_hash)` round-trips all 804, and the four `ECMA-269` volumes stay
distinct.

### Lookup: `best_match`

`Bibliography#search` follows the ETSI/W3C/OGC idiom:

- **Pass the pubid, not the string.** `Type#search_candidates` narrows only when
  the argument is not a `String`, and a block alone never narrows — so the plain
  string this flavor used to pass disabled the binary search however the index
  was built. `pubid_class:` alone fixes nothing; both had to change together.
  Measured: `ECMA-269` now narrows to 12 of 804 rows.
- **Ignore what the reference omits.** `edition` and `volume` are the only two
  ignorable components, because they are index metadata that a document's own
  docidentifier never carries. `number`, `part` and the identifier's CLASS are
  never ignorable: `matches?` compares the class, which is what keeps
  `ECMA-100` and `ECMA TR/100` apart, and what stops a bare `ECMA-418` matching
  `ECMA-418-1`.
- **An unparseable reference finds nothing**, with a warning. There is
  deliberately no substring-scan fallback (OGC has one): an ECMA row renders as
  `ECMA-262 ed17`, so a scan would answer a truncated `ECMA-26` with every
  ECMA-26x document, and an ambiguous answer is worse than none.

**A reference must now parse WHOLE.** The old `parse_ref` regex was unanchored
at the end, so trailing text after a valid prefix was ignored and still
resolved; pubid rejects it. Measured:

| reference | old | new |
|---|---|---|
| `ECMA-6 (draft)` | `ECMA-6` | none |
| `ECMA-6:1991` | `ECMA-6` | none |
| `ECMA-6 2nd edition` | `ECMA-6` | none |
| `ECMA-6 ` (trailing space) | `ECMA-6` | `ECMA-6` |
| ` ECMA-6` (leading space) | none | `ECMA-6` — `parse_ref` strips |

That is the same trade-off as the missing fallback — a strict parse beats an
ambiguous match — and it is the first thing to check against a report that a
reference "used to resolve and now does not". `ecma-6` (lowercase) parsed under
neither.

#### Ordering: latest edition, then lowest volume

That is the order the bespoke `compare_edition_volume` + `min` implemented, kept
deliberately — but the edition is compared **segment-wise as integers**
(`edition_key`), and `r[:file]` breaks the tie because the index sort is not
stable. Comparing the rendered strings made `"9"` beat `"17"`, so 5 of the 421
document families returned an older document than the reference asked for.
Scored against each document's own published date:

| family | string compare | integer compare | dates |
|---|---|---|---|
| ECMA-262 | ed9 | **ed17** | 2018-06 → 2026-06 |
| ECMA-74 | ed9 | **ed22** | 2005-12 → 2025-12 |
| ECMA-402 | ed9 | **ed13** | → 2026-06 |
| ECMA-328 | ed7 | **ed10** | same direction |
| ECMA-109 | ed9 | **ed11** | same direction |

The integer key picks the newer document in all 5. An absent edition sorts below
every present one — right for the 64 edition-less rows (mementos, a few
reports), none of which shares a document with an edition-bearing row.

**`ECMA-262 ed5.1` is the only dotted edition in the whole published corpus.**
It is what forces the segment-wise compare (`5.1` must beat `5`), but since 262's
latest is ed17 the dotted ordering never decides a bare lookup — so it is pinned
by a unit assertion on `edition_key` rather than by an end-to-end example. Do not
"simplify" the key to `to_i`.

The old `match_ref` also matched on a **prefix** (`/^ECMA[-\s]#{id}/`), so
`ECMA-43` matched `ECMA-430…434`. Four families collided this way (418, 43, 35,
13); none of the four changed its answer, so exact matching removed a latent
risk rather than moving results.

#### Verified against the published index

`relaton-data-ecma` publishes `index-v2.zip`. Loaded through
`Bibliography#index`: **804 rows**, all deserialized to identifiers, sorted,
**0** keying on `""`, 804 distinct keys, and `from_hash(to_hash)` round-trips
every row. Live lookups resolve every shape the flavor handles, each to a file
that returns HTTP 200 — a bare `ECMA-269` → ed9, the space form `ECMA 269` →
the same, `ECMA-269 ed3` → vol1, all four `ed3 vol<N>`, `ECMA-262` → ed17
(2026-06), `ECMA-262 ed5.1`, `ECMA-418` vs `ECMA-418-1`, `ECMA-100` vs
`ECMA TR/100`, `ECMA MEM/2021`, and `ECMA-43` narrowed to number `43` alone.

## Testing

- **Framework:** RSpec with VCR cassettes and WebMock.
- **Index fixture:** `spec/ecma/fixtures/index-v2.zip` — the whole published
  index (804 rows), copied verbatim, so the stored shapes are exactly what the
  runtime deserializes. Refresh it with `bundle exec rake spec:update_index_ecma`
  (`tasks/index_fixture_ecma.rb`); `#build` refuses a source that is not a pubid
  index-v2 rather than writing a fixture `Relaton::Index` would reject wholesale.
- It is seeded into the `Relaton::Index` pool by `spec/ecma/support/webmock.rb`,
  built **with `pubid_class:`** — without it the rows stay raw hashes,
  `FileIO#sorted` stays false, and `Type#search` silently stops narrowing, so the
  suite would pass while exercising something the runtime never does. Seeded in
  `before(:each)`, not only `before(:suite)`, because `Index::Pool#type` replaces
  the pooled entry whenever `actual?` says no and `DataFetcher#index` asks for
  the same type with `file:` but no `url:`. With `before(:suite)` alone every
  example after the first data-fetcher one searched a producer index, and the
  consumer then built a third type and went to the network for real. The pool key
  is `type.upcase.to_sym`, so the fetcher's `:ecma` and the consumer's `:ECMA`
  share one slot. (The OGC pattern.)
- **VCR cassettes:** `spec/ecma/vcr_cassettes/` — index downloads are ignored by
  VCR, matched on `INDEXFILE` so a version bump cannot let a real download
  through.
- `spec/ecma/relaton/ecma/index_key_spec.rb` checks the whole fixture corpus for
  the properties the index depends on: every row deserializes, one distinct
  rendered key per row, no empty bsearch key, sorted, and a `to_hash` round-trip.
- A live check of the flavor cannot use `Bibliography.get` behind an HTTP proxy:
  the document fetch goes through **Mechanize**, which does not read
  `http_proxy`/`https_proxy` the way `Net::HTTP` does, so it dies with a
  connection error on a host `curl` reaches. The index download (`Net::HTTP`)
  works, so drive `best_match` and fetch the resolved file with `Net::HTTP`
  instead.
- The `bibdata`/`bibitem` round-trip examples validate XML with Jing, which
  needs a **JVM on PATH**. Without one they fail with `Jing::ExecutionError`;
  that is environmental, not a code defect.
