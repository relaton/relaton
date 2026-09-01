# CLAUDE.md

## Architecture

**Pubid-backed docidentifier.** `Relaton::ThreeGpp::Docidentifier`
(`docidentifier.rb`, `< Bib::Docidentifier`) parses its `content` into a
`Pubid::Tgpp::Identifier` kept in `@pubid`, while the lutaml `content`
attribute stays a plain **string** — `ItemData#create_id` calls
`docid.content.sub(...)`, so the ISO `Type::Pubid` route (which makes `content`
return an object) would break it. Parsing is **soft**: `content=` lazily
`require "pubid"` and rescues `LoadError`/`StandardError`, so a missing pubid
gem or non-3GPP content leaves `@pubid` nil rather than raising.

Before this class existed, 3GPP inherited `Bib::Docidentifier`, whose
`remove_part!` / `remove_date!` / `to_all_parts!` each raise
`NotImplementedError` — and `Bib::ItemData` broadcasts all three to every
docidentifier, so `#to_all_parts` and `#to_most_recent_reference` **raised on
every 3GPP item**. The mapping is 3GPP-specific:

- **`remove_part!` → clears `parts`.** A real, separable component here
  (unlike IALA's, which is a no-op): `TS 29.198-04-1` → `TS 29.198`. `parts`
  is a collection, so it is emptied rather than nil'd — `Identifier#code`
  renders through `parts.map`.
- **`remove_date!` → clears `release` AND `version`.** 3GPP carries no date;
  those two are its version discriminators — the same pair
  `Bibliography#ignored` treats as omittable — so clearing both yields the
  version-agnostic ("most recent") reference `TS 23.207`.
- **`to_all_parts!` → both, plus `all_parts`.** That attribute is inherited
  from the pubid base class, but the Tgpp renderer emits no marker for it, so
  the flag is invisible in the rendered string; the stripped id is the best
  available rendering. Set behind a `respond_to?` guard, as IALA does.

All three no-op safely when `@pubid` is nil, so `ItemData#to_all_parts` and
`#to_most_recent_reference` never raise.

**The `with_publisher` trap.** `Pubid::Tgpp::Identifier#to_s` defaults to
**omitting** the `3GPP ` token — deliberately, so it reproduces the index id
(`TS 23.207:REL-4/4.0.0`). The stored docidentifier `content` *keeps* the
prefix (`Parser#parse_docid` builds `"3GPP #{number}"`), while `docnumber` does
not. So `Docidentifier#refresh_content!` renders
`to_s(with_publisher: true)`; without it every mutation would silently strip
the prefix. This is the one place 3GPP diverges from the IALA template, whose
`refresh_content!` is a bare `to_s`.

**Index (`index-v2`, pubid-keyed).** `INDEXFILE` is the pubid-backed
`index-v2`: 88,464 rows of `_type: pubid:3gpp:{technical-specification,
technical-report}` with `number`/`suffix`/`parts`/`release`/`version`. Every
index call site — `Bibliography#index`, `DataFetcher#index`,
`Processor#remove_index_file` — passes
`pubid_class: ::Pubid::Tgpp::Identifier`. That is what makes `Relaton::Index`
deserialize the rows into identifiers, sort them by `id.root.number`, and let
`Type#search` bsearch. Omitting it on the **producer** side writes v1-shaped
rows under a v2 name, silently (`FileIO#save` only calls `to_hash` when the
value is an instance of `pubid_class`); omitting it on the **consumer** side
leaves the rows raw hashes with `FileIO#sorted` false, so every lookup scans
all 88,464 rows. Measured on the live corpus: 3,767 number buckets, largest
979; a `TS 23.207` lookup narrows to **37 of 88,464**.

`Bibliography#best_match` follows the ETSI/W3C/IALA idiom:

- **Pass the pubid, not the string.** `Type#search_candidates` narrows only
  when the argument is not a `String`, so passing the reference text — which
  this flavor used to do — disables the binary search however the index was
  built. `pubid_class:` alone fixes nothing; both had to change together.
- **Ignore what the reference omits.** `release` and `version` are 3GPP's only
  optional components, so a bare `3GPP TS 23.207` finds the
  `REL-19/19.0.0` row through `ignore: %i[release version]`.
- **`suffix` and `parts` are never ignorable.** They are part of the document
  code (`TS 29.198-04-1`, `TR 00.01U`), not qualifiers, so `TS 29.198` must not
  match `TS 29.198-04-1` and `TR 00.01` must not match `TR 00.01U`.
- **Neither is the document type.** It is the identifier's class, and
  `matches?` compares through `exclude` -> `self.class.new(...)`, so
  `TS 23.207` and `TR 23.207` never match. (No document code in the corpus is
  actually carried by both types — measured over all 88,464 rows — so the
  specs pin this with a negative lookup rather than a fixture pair.)
- **`matches?` needs a pubid new enough to default `parts` to `[]`.** A parsed
  identifier has always had `parts == []`; one deserialized from an index row
  used to have `parts == nil`, and `matches?` is attribute-wise, so every
  part-less row silently failed to match its own reference — 366 of the 387
  fixture rows. Fixed upstream in pubid (`242ad5b`); the flavor briefly carried
  a `to_hash`-comparing workaround, which is gone. If part-less lookups ever
  start returning nil again, check the installed pubid before the flavor.
- **An unrecognized reference raises.** Like ISO and ETSI, the parse error
  propagates out of `search`, so relaton-cli renders `"…" is not a recognized
  standards identifier` (`gems/relaton-cli/lib/relaton/cli/command.rb:324`,
  `subcommand_collection.rb:134`) and API callers rescue it themselves. The
  parse happens **outside** the method-level rescue, whose list is transport
  errors only, so it is never relabelled as a `Relaton::RequestError`.

### Ordering: highest version wins

`min_by { |r| r[:id] }` compared raw strings, so `3GPP TS 23.207` (37 rows)
returned `REL-10/10.0.0` because `"1" < "4"` — neither the newest nor the
oldest, just whichever sorted first as text. The key is now the version,
compared **segment by segment as integers** (`19.0.0` beats `4.0.0`; `5.10.0`
beats `5.9.0`, which a text comparison gets backwards).

Scored against each document's own `date[0].at` over 870 documents in 59
multi-row groups:

| Key | Picks the newest published document |
|---|---|
| version segments, numeric | 51/59 — **86%** |
| release rank, then version | 51/59 — **86%** |
| the old `min_by { r[:id] }` | 1/59 — **2%** |

**Do not add a release key on top.** The two candidate keys picked the same row
in all 59 sampled groups and disagree on only **9 of 3,982** multi-row groups
corpus-wide (99.77% identical) — all draft TRs carried into a later release at
a lower version, e.g. `TR 23.873`, where the release answer is not clearly
better. The cost would be a hand-maintained 27-token table whose order is
**non-monotonic**: the chronological sequence is `Ph1, Ph2, REL-96, REL-97,
REL-98, REL-99, Release 2000, UMTS, REL-4 … REL-21`, so every numeric read of
the token puts REL-99 above REL-19.

Ties break on the rendered id and then the file path, because the index sort is
not stable.

**Known limit — do not try to "fix" the ordering back.** "Newest release" and
"newest publication" are different documents in ~8% of groups, because 3GPP
keeps revising old releases:

```
TS 04.08   newest published: REL-98/7.21.0  2004-01-05
           highest release:  REL-99/8.0.0   2000-06-30
```

A version key returns the second. No key computable from the identifier alone
returns the first: index rows carry only `{id, file}` and `Pubid::Tgpp` has no
date attribute. Closing that gap would need a pubid attribute, an index schema
change and a crawler change.

**Producer side.** `DataFetcher#save_doc` indexes
`docidentifier.detect(&:primary).pubid` through `#index_primary` — the pubid is
already parsed on the model, so nothing re-parses `docnumber`, and
`pubid.to_s` (no publisher token) reproduces the old string key byte-for-byte,
so the index key did not move. `docnumber` still names the output file. An id
pubid cannot rebuild is recorded in `@errors` (the inherited `report_errors`
logs a String value as the message) and the row is **skipped** rather than
indexed unparsed — `Relaton::Index` rejects the whole index on one bad row. The
data file is still written, so the document is unindexed, never lost.

`require "pubid"` sits in `lib/relaton/3gpp.rb` (the IANA/IHO/IALA form),
because `Processor#remove_index_file` names `::Pubid::Tgpp::Identifier` on the
cold path that `spec/relaton/lazy_loading_spec.rb` guards — reached via
`Db#clear` without `Bibliography` ever loading. `Processor` also sets
`@pubid_flavor = :Tgpp`, so `Core::Processor#prefixes` reads
`Pubid::Tgpp.prefixes` (`["3GPP"]`).

## Testing

- `bundle exec rake spec:3gpp` — run the 3GPP suite.
- Specs live in `spec/3gpp/relaton/3gpp/` and run self-contained (see the root
  `CLAUDE.md` Testing section).
- **Index fixture.** `spec/3gpp/fixtures/index-v2.zip` is a curated subset of
  the published index — never the full 88,464 rows, and never hand-written.
  `bundle exec rake spec:update_index_3gpp` regenerates it;
  `tasks/index_fixture_3gpp.rb` names each document group and the rule it pins
  (`TS 23.207` version ordering, `TS 05.05` legacy release tokens, `TS 04.08`
  the known limit, `TS 29.198-04-1` parts, `TR 00.01U` suffix, `TS 29.215` the
  release-less row). Rows are copied verbatim except that the `:id` string is
  converted with `Pubid::Tgpp::Identifier.parse(...).to_hash` — exactly what
  `DataFetcher` writes, and byte-identical on round-trip over all 88,464 rows,
  so the fixture is shape-faithful even before `relaton-data-3gpp` publishes
  its own v2. Point `IndexFixture3gpp::SOURCE` at `index-v2.zip` once it does.
- `spec/3gpp/support/webmock.rb` seeds the fixture into the `Relaton::Index`
  pool **with `pubid_class:`** — without it the suite would pass while
  exercising something the runtime never does. It re-seeds in `before(:each)`,
  not only `before(:suite)`, because `DataFetcher#index` asks for the same type
  with `file:` but no `url:` and `Pool#type` then replaces the entry.
  `Pool#type` upcases its key, so `Bibliography`'s `"3GPP"` and
  `DataFetcher`'s `"3gpp"` are the same pooled entry, `:"3GPP"`.
- **VCR cassettes:** `spec/3gpp/vcr_cassettes/`. Index downloads are ignored by
  VCR (matched as `index-v\d+\.zip`, so the next `INDEXFILE` bump does not
  start recording them) and served from the fixture instead.
