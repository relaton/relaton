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
component (e.g. `CCSDS 121.0-B-3` → `CCSDS 121-B-3`) and sets `all_parts` on the
pubid; note pubid-ccsds does **not** render an `(all parts)` marker the way
pubid-iso does, so the flag is currently invisible in the string form — the
part-stripped id is the best available rendering. This mirrors
`lib/relaton/iec/model/docidentifier.rb`; the shared skeleton is intentionally
duplicated per flavor for now (to be hoisted into `Bib::Docidentifier` once every
flavor's id is Pubid-backed).

**Translation relations use pubid's subset match.**
`Data::Fetcher#search_relations` and `#search_translations` derive a
language-less identifier from the document's own id and select index rows with
`bibid_pid === row[:id]` (`Pubid::SubsetMatch`, the reference on the left). The
language is the only component the derived id leaves out, so a translated row
matches and another edition of the same number does not.
`HitCollection#rows` keeps `exclude(:edition)` instead: a CCSDS reference that
omits the language must **not** reach a translation, and a nil component is a
wildcard for `===`.

**Known gap, older than that swap:** `#search_relations` excludes the document's
own row with `row[:id] == bib.docidentifier.first.content`, which compares a
`Pubid::Ccsds::Identifier` with a `String` and is therefore always false. A
re-crawl over an index that already holds the document can give it a relation to
itself. The fix is to compare `row[:id].to_s`, or to parse the content once; it
needs a regression example, because no spec yields the document's own row.

## Development

- `bundle install` — install dependencies
- `bundle exec rake spec` — run tests
- `bundle exec rubocop` — lint

## Testing

- **Framework:** RSpec with VCR cassettes and WebMock
- **Index fixture:** `spec/fixtures/index-v1.zip` is pre-loaded into `Relaton::Index` pool in `before(:suite)` (configured in `spec/support/webmock.rb`). Run `rake spec:update_index` to refresh from relaton-data-ccsds.
- **VCR cassettes:** `spec/vcr_cassettes/` — index download requests are ignored by VCR (handled by fixture).
