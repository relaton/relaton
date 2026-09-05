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

### The gem produces `index-v2`; the data repo derives `index-v1`

`INDEXFILE` is the pubid-backed `index-v2`: rows are `Pubid::Ecma::Identifier`
hashes (`_type: pubid:ecma:{standard,technical-report,memento}` with
`number`/`part`/`edition`/`volume`). `DataFetcher#index` passes
`pubid_class: ::Pubid::Ecma::Identifier`. Omitting it on the **producer** writes
v1-shaped rows under a v2 name, silently — `FileIO#save` calls `to_hash` only
for instances of `pubid_class`.

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

### `INDEXFILE_V1` is temporary, and read-side only

`Bibliography` and `Processor#remove_index_file` still name `INDEXFILE_V1`,
because `relaton-data-ecma` has not republished yet — `index-v2.zip` is a 404
there today, so pointing the consumer at it would break every live lookup. It is
a read-side name, not a second published index.

Delete `INDEXFILE_V1` and its two call sites with the consumer migration
(`HANDOFFS/relaton__relaton__ecma-consume-index-v2.md`), which replaces
`Bibliography`'s regex `parse_ref`/`match_ref`/`compare_edition_volume` with the
`best_match` shape from `lib/relaton/ogc/hit_collection.rb`.

### Two measurements the consumer migration needs

Taken here against the published 804-row index, so the follow-up does not have
to re-derive them.

**Edition ordering is a string compare today**, so `"9"` beats `"17"`. 5 of the
421 document families return the wrong document, and each moves to the newer one
under a segment-wise integer compare:

| family | today | correct | published dates |
|---|---|---|---|
| ECMA-262 | ed9 | ed17 | 2018-06 → 2026-06 |
| ECMA-74 | ed9 | ed22 | 2005-12 → 2025-12 |
| ECMA-402 | ed9 | ed13 | same direction |
| ECMA-328 | ed7 | ed10 | same direction |
| ECMA-109 | ed9 | ed11 | same direction |

Editions are dotted (`5.1` is real, on ECMA-402 and ECMA-262), so compare
segment-wise as integers — a text compare gets both `10 > 9` and `5.1 > 5`
backwards.

**`match_ref` matches on a prefix** (`/^ECMA[-\s]#{id}/`), so `ECMA-43` also
matches `ECMA-430…434`. Four families collide this way (418, 43, 35, 13). None
of the four changes its answer today, so `Pubid::Identifier#matches?` removes a
latent risk rather than moving results. `matches?` also discriminates the type —
`ECMA-100` does not match `ECMA TR/100` — and treats `part` as never ignorable,
so `ECMA-418` does not match `ECMA-418-1`.

No cassette-covered reference moves under either change: `ECMA-6`, `ECMA 269`,
`ECMA-269 ed3`, `ECMA-269 ed3 vol2`, `ECMA-262 ed5.1`, `ECMA-370`,
`ECMA TR/18` and `ECMA MEM/2021` all resolve to the same file before and after.

## Testing

- **Framework:** RSpec with VCR cassettes and WebMock.
- **Index fixture:** `spec/ecma/fixtures/index-v1.zip` (a copy of the published
  index) is seeded into the `Relaton::Index` pool by
  `spec/ecma/support/webmock.rb` — in `before(:each)`, not only
  `before(:suite)`, because `Index::Pool#type` replaces the pooled entry
  whenever `actual?` says no and `DataFetcher#index` asks for the same type with
  `file:` but no `url:`. With `before(:suite)` alone every example after the
  first data-fetcher one searched a producer index, and the consumer then built
  a third type and went to the network for real. (The OGC pattern.) The fixture
  stays on v1 because the consumer does; it moves with the consumer migration.
- **VCR cassettes:** `spec/ecma/vcr_cassettes/` — index downloads are ignored by
  VCR, matched on `INDEXFILE_V1` so a version bump cannot let a real download
  through.
- `spec/ecma/relaton/ecma/index_key_spec.rb` checks the whole fixture corpus for
  the one property the index depends on: one distinct rendered key per row.
- The `bibdata`/`bibitem` round-trip examples validate XML with Jing, which
  needs a **JVM on PATH**. Without one they fail with `Jing::ExecutionError`;
  that is environmental, not a code defect.
