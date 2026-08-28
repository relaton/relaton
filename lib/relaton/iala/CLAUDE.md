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

**Index (`index-v2`, pubid-keyed).** `INDEXFILE` is the pubid-backed
`index-v2` published by `relaton-data-iala`: 701 rows of
`_type: pubid:iala:*` with `number`/`edition`/`language`. Every index call site
(`Bibliography#index`, `Processor#remove_index_file`) passes
`pubid_class: ::Pubid::Iala::Identifier` — that is what makes `Relaton::Index`
deserialize the rows into identifiers, sort them by `id.root.number`, and let
`Type#search` bsearch. Omitting it leaves the rows as raw hashes and
`FileIO#sorted` false, so every lookup scans all 701 rows, silently. That was
the state before this flavor adopted the W3C pattern; the data repo already
published a pubid-shaped `index-v2`, only the consumer was unwired.

`Bibliography#best_match` follows the ETSI/W3C idiom:

- **Pass the pubid, not the string.** `Type#search_candidates` narrows only when
  the argument is not a `String`, so passing the reference text — which this
  flavor used to do — disables the binary search however the index was built.
- **Ignore what the reference omits.** `edition` and `language` are IALA's only
  optional components, so a bare `IALA M0001` finds the `Ed 9.0 (E)` row through
  `matches?(row_id, ignore: %i[edition language])`.
- **The document type is never ignorable.** It is the identifier's class, and 17
  of the 309 index numbers are shared by two types (`R1001` and `C1001` are
  different documents), so `matches?` must keep them apart.
- **Newest edition wins, deterministically.** Editions are dotted versions and
  must be compared segment-by-segment as integers: `"10.0"` is newer than
  `"9.0"` but loses as a string. No published edition has a segment above 9
  today, so this is latent — the same bug already fixed for ETSI. Ties break on
  the edition text and then the file path, because the index sort is not stable.
  Among rows of one edition the language-neutral record wins: it is the base
  document, the others are translations.
- **An unparseable reference still searches.** `parse_ref` returns nil rather
  than raising, and the search falls back to the previous full-scan substring
  match on `id.to_s`.

`require "pubid"` moved to `lib/relaton/iala.rb` (the IANA/IHO form), because
`Processor#remove_index_file` names `::Pubid::Iala::Identifier` on the cold path
that `spec/relaton/lazy_loading_spec.rb` guards. `Docidentifier` keeps its own
lazy, `LoadError`-rescuing require: it is reached by deserialization, which must
not depend on the flavor entry file having been loaded.

## Testing

- `bundle exec rake spec:iala` — run the IALA suite.
- Specs live in `spec/iala/relaton/iala/` and run self-contained (see the root
  `CLAUDE.md` Testing section).
- `spec/iala/fixtures/index-v2.zip` is a 19-row curated subset of the published
  index, copied row-for-row so the stored shapes stay verbatim. It covers the
  matching rules above: a multi-edition document (`R0101`, editions `2` and
  `3.0`), a four-language document (`R0106`), a number shared by two types
  (`R1001` / `C1001`), a sub-part folded into the number (`C0103-1`), and the
  language-neutral/translation split. `spec/iala/support/webmock.rb` seeds it
  into the `Relaton::Index` pool **with `pubid_class:`** — without that the
  suite would pass while exercising something the runtime never does.
