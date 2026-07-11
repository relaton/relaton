# CLAUDE.md

## Architecture

**Pubid-backed docidentifier.** `Relaton::Iala::Docidentifier`
(`docidentifier.rb`, `< Bib::Docidentifier`) parses its `content` into a
`Pubid::Iala::Identifier` kept in `@pubid`, while the lutaml `content` attribute
stays a plain string for serialization. Parsing is **soft**: `content=` lazily
`require "pubid"` + `require "pubid/iala"` (pubid core must load first for
`Pubid::PrefixesSupport`) and rescues `LoadError`/`StandardError`, so a missing
pubid gem or non-IALA/unparseable content leaves `@pubid` nil rather than raising.

It implements the base class's abstract `remove_part!` / `remove_date!` /
`to_all_parts!` by mutating the pubid and re-rendering via `refresh_content!`
(which writes through the aliased `store_content` — the inherited string setter —
so in-place mutations aren't clobbered by a re-parse). IALA's identifier models
only `publisher`/`number`/`edition`/`language`, so the mapping is IALA-specific:

- **`remove_date!` → clears `edition`.** IALA carries no date component; `edition`
  is its version discriminator, so this yields the version-agnostic ("most
  recent") reference, e.g. `IALA S1070 Ed 2.0` → `IALA S1070`.
- **`remove_part!` → clears the (unused) `part`/`subpart` attributes.** A no-op
  for the rendered string today: IALA folds any subpart inline into `number`
  (e.g. `0103-1`), so the part is not a separable component. Implemented anyway
  so it never raises, and it starts working automatically if pubid-iala ever
  models `part` separately.
- **`to_all_parts!` → `remove_part!` + `remove_date!` + `all_parts = true`.**
  Drops the edition and flags the identifier; note the IALA renderer does not
  emit an all-parts marker, so the flag is invisible in the string form — the
  edition-stripped id is the best available rendering. Mirrors
  `lib/relaton/iec/model/docidentifier.rb`.

All three no-op safely when `@pubid` is nil, so `Bib::ItemData#to_all_parts` /
`#to_most_recent_reference` never raise on IALA items.

## Testing

- `bundle exec rake spec:iala` — run the IALA suite.
- Specs live in `spec/iala/relaton/iala/` and run self-contained (see the root
  `CLAUDE.md` Testing section).
