# CLAUDE.md

## Architecture

**Pubid-backed docidentifier.** `Relaton::Ccsds::Docidentifier`
(`model/docidentifier.rb`, `< Bib::Docidentifier`) parses its `content` into a
`Pubid::Ccsds::Identifier` kept in `@pubid`, while the lutaml `content` attribute
stays a plain string for serialization. It implements the base class's abstract
`remove_part!` / `remove_date!` / `to_all_parts!` by mutating the pubid graph
(walking the `base` chain for supplements/corrigenda) and re-rendering
via `refresh_content!`. Unparseable content falls back to the raw string. It is
wired into `model/item.rb` (`attribute :docidentifier, Docidentifier`) so
`from_xml`/`from_yaml` and `DataParser#parse_docidentifier` yield this class.
`remove_date!` is effectively a no-op today — CCSDS ids carry no date component —
but is implemented for parity with ISO/IEC. `to_all_parts!` drops the part
component (e.g. `CCSDS 121.0-B-3` → `CCSDS 121-B-3`), freezes that rendering
into `@raw_content` (since `content` is live-derived from `@pubid`), then
wraps `@pubid` in pubid's `AllParts`. pubid-ccsds has no dedicated `AllParts`
subclass — unlike pubid-iso — so the wrapper is the generic
`Pubid::AllPartsIdentifier`: `content` stays the plain part-stripped id, but
`#pubid` itself, read directly, now answers `all_parts? == true` and renders
WITH pubid's generic "(all parts)" marker, since it's the wrapper. This
mirrors `lib/relaton/iec/model/docidentifier.rb`; the shared skeleton is
intentionally duplicated per flavor for now (to be hoisted into
`Bib::Docidentifier` once every flavor's id is Pubid-backed).

**Translation relations use pubid's subset match.**
`Data::Fetcher#search_instance_translation` reads the document's **already
parsed** id from `bib.docidentifier.first.pubid` (not `content`, which it would
re-parse), derives the language-less reference with `pubid.exclude(:language)`,
and picks the branch by `bibid == pubid` — no language means an instance
(`#search_translations`), a language means a translation (`#search_relations`).
This is more correct than the old `TRRGX` string test: `content` returns
`@pubid.to_s`, which reorders components, so a translated corrigendum
(`CCSDS 320.0-B-1-S - German Translated Cor. 1`) put the language mid-string and
the `$`-anchored `TRRGX` missed it; `exclude(:language)` strips the language down
the whole base chain. `TRRGX` still serves `translation_relation_types` and
`DataParser#relation_type`, which match raw relation-id strings.
`#search_relations` and `#search_translations` receive that pubid and select
index rows with `row[:id].exclude(:language) == bibid_pid` — a
language-agnostic match, so a translated row and the instance both match while
another edition of the same number does not. This does **not** use `===`:
pubid declares CCSDS `language` `subset_strict`, so a nil reference language
means "has none" (a wildcard would be wrong for `HitCollection`, where a
language-less user reference must not reach a translation). `exclude(:language)`
drops the language from the row on both sides, mirroring
`HitCollection#rows` (`r[:id].exclude(:edition) == pubid`).

`HitCollection#rows` keeps `index.search(pubid, exact: true)` for an edition
reference, although `language` is strict now. CCSDS `suffix` is still a nil
wildcard in pubid, so the bare `index.search(pubid)` makes `CCSDS 101.0-B-4`
also return the historical `CCSDS 101.0-B-4-S` (260 such pairs in the index
fixture). The `hit_collection_spec` "historical and a translated sibling"
example guards this. Drop `exact: true` only after pubid declares `suffix`
`subset_strict` too.

`#search_relations` excludes the document's own row with
`row[:id] == bib.docidentifier.first.pubid` — pubid to pubid. It compared a
`Pubid::Ccsds::Identifier` with a `String` (`.content`) before and was always
false, so a re-crawl over an index that already held the document gave it a
relation to itself. Covered by the `#search_relations` "excludes the document's
own row" example.

## Development

- `bundle install` — install dependencies
- `bundle exec rake spec` — run tests
- `bundle exec rubocop` — lint

## Testing

- **Framework:** RSpec with VCR cassettes and WebMock
- **Index fixture:** `spec/fixtures/index-v1.zip` is pre-loaded into `Relaton::Index` pool in `before(:suite)` (configured in `spec/support/webmock.rb`). Run `rake spec:update_index` to refresh from relaton-data-ccsds.
- **VCR cassettes:** `spec/vcr_cassettes/` — index download requests are ignored by VCR (handled by fixture).
