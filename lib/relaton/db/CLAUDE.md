# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run the umbrella (Db) suite — specs live in spec/relaton/ and run from there
bundle exec rake spec:relaton

# Run a single spec file (specs are CWD-relative, so cd into the suite dir)
cd spec/relaton && bundle exec rspec db_spec.rb

# Run a specific test by line number
cd spec/relaton && bundle exec rspec db_spec.rb:234

# Lint
bundle exec rubocop
```

## Architecture

Relaton is a Ruby gem that fetches, caches, and manages bibliographic references to technical standards from 25+ organizations (ISO, IEC, IETF, NIST, IEEE, etc.).

### Plugin Registry Pattern

**Relaton::Registry** (singleton) auto-discovers and manages backend processor gems (relaton-iso, relaton-iec, relaton-ietf, etc.). Each processor implements the **Relaton::Processor** interface (`get`, `from_xml`, `from_yaml`, `grammar_hash`, `prefix`, `defaultprefix`). The registry routes reference codes to the correct processor by matching prefixes (e.g., "ISO 19115" → `:relaton_iso`).

Registration is **lazy**: `register_gems` requires only each flavor's lightweight `…/processor` file, never the heavy flavor top-level, so flavor deps load on first use rather than at startup. Any processor method touching a flavor constant must `require_relative "../<flavor>"` first — see the root `CLAUDE.md` "Registry is lazy" note and `spec/relaton/lazy_loading_spec.rb`.

### Global prefix register (relaton-db#103)

Separate from the reference-dispatch matching above, each processor declares the
**global document-ID prefixes its SDO owns** via `@prefixes` (Array<String>) in
`initialize` — e.g. NIST → `%w[NIST NBS]`, ISO → `["ISO", "ISO/IEC", "IEC/ISO",
"ISO/IEC/IEEE"]`. `Core::Processor#prefixes` defaults to `[prefix]`, so the ~24
single-prefix flavors need no declaration; only multi-/conflicting-prefix
flavors (iso, iec, nist, ieee, bsi) set it. **Joint prefixes are listed
symmetrically** by every co-publisher (both ISO and IEC list `ISO/IEC`; all three
of iso/iec/ieee list `ISO/IEC/IEEE`) so the register returns every owning flavor.
This is a distinct exact-match list, *not* the `@defaultprefix` regex — those
require a trailing `\s` and can't match a bare prefix like `"ISO/IEC"`.

Two lookups over it:
- `Registry#processors_by_prefix(prefix)` → the owning **processor objects**,
  case-insensitive exact match, in registration (`SUPPORTED_GEMS`) order. **Lazy**
  — touches no flavor constant. Use this if you must stay lazy.
- `Relaton.prefix_flavor(prefix)` (in `lib/relaton.rb`) → the owning **flavor
  module(s)** as an Array (`[]` if none). Dereferencing a module constant
  triggers that flavor's autoload, so this **loads** the matched flavor(s) — by
  design, since the caller asked for the module.

Prefixes are **sourced from pubid** — the source of truth for each SDO's
identifier grammar (per @ronaldtse's review on relaton-db#103). A processor sets
`@pubid_flavor` to its Pubid module name (e.g. `:Iso`) in `initialize`, and
`Core::Processor#prefixes` lazily reads `Pubid::<Flavor>.prefixes`
(`require "pubid"` on first call, memoized). pubid returns each SDO's leading
identifier tokens, including non-obvious ones (BSI `DD`, NIST `FIPS`) and joint
forms listed symmetrically across co-publishers (`ISO/IEC` in both ISO's and
IEC's lists). Flavors with no `@pubid_flavor` fall back to `[prefix]`. The pubid
API (`Pubid.prefixes(flavor)` / `Pubid.prefix_flavors` / the `PrefixesSupport`
mixin) was specified in `HANDOFFS/metanorma__pubid.md` and implemented upstream;
relaton pins the pubid version that carries it.

Conflicting prefixes where the *same* base identifier is co-published as distinct
per-publisher documents (e.g. `IEC 80000-13` vs `ISO 80000-3` — different cover,
location, even foreword) are a **separate follow-up**: the register already
returns both flavors, but returning the correct publisher-specific *content*
touches `Db#fetch`, not the prefix list.

Scope note: only *prefixes* live here. Broader "SDO/organization metadata" (org
names — relaton-db#132; logos — metanorma#346) was deliberately kept **out** of
relaton proper, destined for a separate store/gem; don't add it to the processors.

### Db (lib/relaton/db.rb) — Main Public API

`Relaton::Db#fetch(ref, year, opts)` is the primary entry point. It:
1. Routes the reference with `Registry#route` (see **Routing** below)
2. Handles combined references (`+` for derivedFrom, `,` for amendments) in `combine_doc`
3. Delegates to `check_bibliocache` which manages the dual-cache lookup and network fetch flow

### Routing (`Registry#route`, relaton#205)

One rule for `fetch`, `fetch_db`, `fetch_async`, `fetch_std` and `docid_type`.
It returns `[stdclass, pubid]`:

1. **Parse with pubid, and keep only the parsing flavor's own exact parse.**
   `Pubid.parse` falls back to a partial parse by any flavor (`ATN5014` → `IEC
   ATN5014`), and a permissive grammar reads another publisher's string exactly
   (`ISO REF` as IEC, `ABC 123456` as GB, a bare DOI as UN). A parse counts only
   when it renders the reference back (`to_s == reference`, pubid's own
   round-trip test) **and** the flavor claims the reference by one of its
   `Pubid::<Flavor>.prefixes` (`prefix_of?`: the reference ends there or goes on
   with a separator; a prefix that ends in punctuation, `doi:`, needs none).
   A flavor whose identifiers print without a publisher token opts out of the
   claim with `Core::Processor#bare_identifiers?`: OGC (`19-025r1`, the form
   its documents carry) and 3GPP (`TS 23.207:REL-18/18.0.0`, its index form).
   Without the opt-in both raised, and `TR 00.01U:UMTS/3.0.0` went to JIS by
   the `TR` regex. A URN no flavor owns (`urn:foo:bar`) makes `Pubid.parse`
   raise a plain `ArgumentError`, which counts as no parse.
2. **Route by class ancestry** (`processor_by_pubid`), so the registration order
   does not matter (a spec routes with the processors reversed).
3. **A co-published identifier: the printed form decides.** There is no
   canonical form of it (pubid#469), and `Pubid.parse` tries the owners of a
   joint prefix alphabetically, so `ISO/IEC 27001` parses as IEC. A reference
   that starts with a prefix several flavors own (`joint_prefixes`: `ISO/IEC`,
   `IEC/ISO`, `ISO/IEC/IEEE`) routes to the owner whose own prefix is the first `/` token:
   `ISO/IEC …` → ISO, `IEC/ISO …` → IEC. The parsed pubid is kept only when it
   is that flavor's. This is **relaton's routing policy, not a pubid gap**: the
   same string `ISO/IEC 27001:2022` is in both the ISO and the IEC catalogs, and
   pubid must not elect one reading of it nor route records (pubid#469). The
   #205 comment puts the choice here — the printed form first, then the
   co-publisher's flavor when the first one has no record (**Co-publisher
   fall-through**, below).
4. **Else the prefix regex** (`class_by_ref`): combined references, the
   `PREFIX(code)` wrapper, `IEV`, URNs, and spellings a flavor normalizes on
   render (`OGC 19-025r1`, `UN TRADE/…`, `3GPP TS …`, `IEEE 802.11-2016`).
5. **Else `Relaton::UnknownReferenceError`** (`< Relaton::Error`).
   `fetch_async` logs it and yields nil; `docid_type` returns `[nil, code]`;
   relaton-cli logs it and returns no document.

**One parse per fetch (#205 PR 2).** `Db#query_and_key` turns the routed pubid
into the **query pubid** once (`Core::Processor#query_pubid(ref, opts,
parsed)`: the routed parse, else `#cache_pubid`, kept only when it is a
`Pubid::Identifier`), keys the cache with it (`#cache_key(ref, year, opts,
query)`, which folds year/all_parts on **copies**), and hands that same object
to the flavor: `processor.get(query || code, year, opts)`. So
`db.fetch("ISO 19115-1")` is one grammar parse, and `db_spec.rb` counts it.
The year and `all_parts` still reach `get` as arguments; the pubid is unfolded.
A nil query pubid (no pubid class, a policy miss such as `IEV`, a CCSDS
format) sends the String and leaves the query uncached. `fetch_api` keeps the
String for its URL. If `urn_to_code` rewrote the reference, the routed parse is
of another string, and `query_pubid` parses the code. IEC's `urn_to_code` acts
on a `urn:` only: `Relaton::Iec.urn_to_code` splits on `:`, and it used to
rewrite `IEC 60034-1:1969+AMD1:1977+AMD2:1979+AMD3:1980 CSV` into
`1979+AMD3 1980 CSV`.

**Co-publisher fall-through (#205 PR 3).** A not-found from the lead flavor is
not the last word for a co-published document. The organizations serve the
joint portfolio by their own policies (IEC serves ISO-led documents, ISO serves
IEC-portfolio ones; the IEC index fixture holds ~7,450 `ISO/IEC` rows), so
`Db#fetch` (and `fetch_db`, `fetch_async`, and a `fetch_std` that routes) then
asks the co-publishers' flavors (`Db#copublisher_fetch`):

- **Order: the parsed pubid's, lead first.** `Core::Processor#copublishers(pubid)`
  reads the publishers after the lead from the query pubid — `copublishers` for
  ISO and IEC, IEEE's `publishers`/`copublisher` through its override. pubid#472
  made the order the printed one. `Registry#class_by_publisher` maps each to the
  flavor whose own prefix it is (`ASTM`, `IDF` have none, and are skipped).
- **Each co-publisher uses its own flavor end to end**: its own parse of the
  String (`ISO/IEC 27001` reaches IEC as a `Pubid::Iec` pubid), its own cache
  key and bucket, its own `not_found` row. A second fetch reads ISO's
  `not_found` and IEC's cached document with no network call. No row crosses
  flavors, because `bib_retval` must read XML with the flavor that wrote it.
- **A co-publisher whose flavor gives no pubid for the lead's form is
  skipped**, with a log line: a parse error (`IEEE/ISO 11073-10101` in ISO or
  IEC), or a flavor that reads the form as a miss (IEEE's `cache_pubid` gives
  nil for `ISO/IEC/IEEE 15288:2023/DAmd 1`). Without that rule IEEE would get
  the String with no cache key, so every fetch would call it again. There is
  no re-render into the co-publisher's arrangement: pubid#469 elects no
  reading, and #472's "ISO face" keeps the printed publisher order. **Only the
  probe parse is rescued** (`Db#copublisher_query`): a parse error from inside
  the co-publisher's `get` is a flavor or data bug, and it propagates.
- The co-publishers get the reference **as the lead read it**
  (`strip_id_wrapper`: no `ISO(…)` wrapper, no en dash). Without that, a
  wrapped or en-dash reference raised after the lead's miss.
- **Not a fall-through:** a lead hit; a `Relaton::RequestError` (a transport
  failure is not "not found", and it propagates); a flavor the caller names in
  `fetch_std`; each part of a combined reference (`combine_doc` calls
  `check_bibliocache` directly); a URN, which reaches the co-publisher as the
  URN String that its flavor cannot parse, so it is skipped.
- **Known cost of the per-flavor rows:** a repeat fetch logs the lead's
  "not found in cache" before IEC's cached document answers, and when the lead
  later gains the record, the co-publisher's copy answers until the lead's
  `not_found` row expires (60 days) or the caller passes `no_cache`.
- On the pinned pubid (`27454393`, pre-#472) an IEEE joint development lists
  its `publishers` in a reordered form (`IEEE/ISO/IEC 8802-3` → ISO, IEC, IEEE).
  It does not change an answer today: ISO and IEC cannot parse an IEEE-led form,
  so both are skipped.

**The flavor contract for `get`** (every flavor in this gem keeps it):

- **Accept a String or the flavor's pubid.** Parse only a String; a String-only
  rewrite (`IEV`, `upcase`, an en dash, a `BIPM ` prefix) stays in the String
  branch. Unwrap an `AllParts` pubid the way the String `(all parts)` is read.
- **Never mutate the pubid.** It is also the cache key, and `to_all_parts`
  wraps the same object. Copy before a setter (`exclude`, or
  `pubid.class.from_hash(pubid.to_hash)`); ISO `root.date=`, IEC `date=` and
  JIS `year=` used to write into the caller's object.
- **Use `ref.to_s` for text** — log keys (`Util.info …, key: ref.to_s`; the
  JSON log formatter would serialize a pubid), portal search text, messages.
  Routing's own parse prints back as the reference. A pubid from
  `#cache_pubid` (prefix-fallback routing, a named `fetch_std`, a
  `combine_doc` piece, a `urn_to_code` rewrite) can print a **normalized**
  form: `NISTIR 8200` → `NIST IR 8200`, `NIST SP 800-38A Add` → `… Add.`,
  `CIPM Meeting 43` → `CIPM 43rd Meeting`, `IEEE 528` → `IEEE Std 528`,
  `… Expert commentary` → `… Expert Commentary`, and OGC and 3GPP print with no
  publisher token. So a text lookup must accept the normalized print: BSI's
  `ExComm` rewrite is case-insensitive for this reason, and 3GPP logs with
  `to_s(with_publisher: true)`.
- `spec/relaton/support/umbrella.rb` has the `pubid_of("ISO 19115-1")` matcher
  for a stubbed `get`'s first argument.

`Relaton::Db#fetch_all(text, edition, year)` searches cached entries, filtering by text content (via `match_xml_text?`), edition, and/or year. Returns an array of deserialized bibliographic items from both local and global caches.

The dual-cache strategy uses a **global cache** (`~/.relaton/cache`) and an optional **local cache** (project-level). `check_bibliocache` checks local first, falls back to global, and syncs between them.

### Cache (lib/relaton/db/cache.rb) — pubid-keyed index on lutaml-store

relaton#189 item 2 / relaton#204. Two lutaml-store `FileSystem` stores under
`<dir>/v2/`:

- **`rows/`** — the index. One store key per **bucket**, `<flavor>/<root number>`
  (`iso/19115`), whose value is the list of the bucket's `CacheEntry` rows
  (`lib/relaton/db/cache_entry.rb`): `id` (the pubid's `to_hash`) or `key` (a
  legacy string), `status` (`doc` / `not_found`), `file`, `fetched`. A lookup
  reads one small bucket; a write is one atomic `update` of it. A `_versions`
  key holds each flavor's `grammar_hash`; a changed one drops that flavor's
  rows and documents on open.
- **`docs/`** — the XML documents. **Several rows can point to one document.**
  A fetch whose answer has another identifier than the query
  (`ISO 19115-1` → `ISO 19115-1:2014`) writes the query row and the item row,
  both naming the same file. There are no redirect entries. A document is
  deleted with the last row that points to it; a row whose document is gone is
  a miss.

Matching: the **exact** row first (canonical `to_hash`, not pubid `==`, which
is false after a `from_hash` round trip for some flavors, e.g. UN). Only a
**dated** query then falls back to `query === row_id` in the same bucket —
an undated query keeps its own row, so the 60-day expiry of undated entries
still applies and it never answers with another query's year-stripped copy.
**`===` alone is too wide here**: it reads an omitted `part` as "any part", so
`ISO 19115:2003 === ISO 19115-1:2003` (and the same for IEC, BSI, JIS, GB).
`Cache#subset_of?` therefore also requires that every component the row adds
(at any depth) is allowed: only a language for the dated fallback
(`LANGUAGE_COMPONENTS`), a year/date/month or a language for the date-range
`candidates` (`EDITION_COMPONENTS`). A row with no `root.number` (DOI, ISBN)
goes to one of 256 digest buckets (`<flavor>/~<hex>`).

Expiry (`Cache#valid_row?`): an undated row, and **every** `not_found` row,
is valid for 60 days (`UNDATED_TTL`) from its `fetched` date; only a `doc`
row looked up with a `year` argument never expires (`fetch("ISO 9999:2030")`
passes no `year`, so its rows expire too). A `not_found` for a dated query
used to stay for ever (`year || age < 60`), so a document published after
the first miss was never fetched (#204).

Locking and atomic writes come from lutaml-store (≥ 0.3.2 — 0.3.0's
FileSystem adapter was unsafe, lutaml/lutaml-store#17): an exclusive `flock`
on `<root>/.lock` plus a per-root Monitor for `update`/`transaction`, and temp
file + rename per write. `Cache#store` writes the document and both rows in
one `rows` transaction; the lock order is always `rows`, then `docs`.
Two specs check this with the real lock, in two processes (#204):
`db_cache_spec.rb` ("keeps every row when two processes write") and
`db_spec.rb` ("keeps one consistent cache when two processes fetch", the whole
`Db#fetch` path). They start the processes with `Process.spawn`
(`run_children`, `spec/relaton/support/child_processes.rb`), not `fork`, so
they also run on Windows, where production has two separate commands that
share `~/.relaton/cache`. A child is a fresh Ruby: RSpec stubs do not reach
it, so its script replaces what it needs (the `Db` spec redefines ISO's
`Bibliography.get`). A spawned child loads its code for seconds and works
for less than one, so each script calls `start_barrier!` after its requires,
and the children start their work together. Both specs also put every row in
**one bucket** on purpose: two processes that write the same rows, or
different buckets, hide a lost update (the `Cache` spec used 50 buckets
before, and passed with no lock). Measured with the `flock` made a no-op
(loaded into the children through `RUBYOPT`): the `Cache` spec failed 5 of 5
runs and the `Db` spec 4 of 5; with a sleep added inside `update` too, both
failed 3 of 3. With the real lock they passed 20 of 20.

An old file-per-key cache (anything in `<dir>` beside `v2/`) is **moved** to
`<dir>-v1.bak` on open, never deleted — **once**: when the `.bak` exists the
old entries stay where they are, because an older relaton sharing the
directory writes the old layout again, and v2 ignores it.

Keys: a parsed pubid; a wrapped string (`ISO(ISO 19115-1)`), which the cache
parses through the prefix's processor — `load_entry`/`save_entry` still take
it; or a plain string no processor owns (bucket `_key/<string>`).

Values: `Db` and `Cache` pass the document XML (`String`) or a
`Relaton::Db::NotFound` (`Data` with `fetched`, in `cache_entry.rb`), never a
marker string. `Db` reads with `Cache#read` and tests `is_a?(NotFound)`; keep
`not_found` regexes out of `db.rb` (`db_spec.rb` guards it). The string API is
kept for compatibility: `Cache#[]` and `Db#load_entry` return
`"not_found <date>"` (`NotFound#to_s`), and `Cache#[]=`/`#store` still accept
that string, which `Cache#coerce` turns into a `NotFound` at the entrance.

### WorkersPool (lib/relaton/db/workers_pool.rb)

Thread pool for `fetch_async`. Default 10 threads per processor, overridable via `RELATON_FETCH_PARALLEL` env var.

### Cache key

`Db#query_and_key` asks the processor: `Core::Processor#cache_key(ref, year,
opts, query)` takes the query pubid (above; else it parses the reference **as
written** with the routed flavor's pubid class, `#cache_pubid` →
`pubid_class.parse`), then folds `year`
(`#fold_year`) and `all_parts` (`to_all_parts`) into the pubid.
`#pubid_class` reads `@pubid_identifier`, else `@pubid_flavor` —
`@pubid_identifier` exists so a flavor can key its cache with pubid without
also sourcing `#prefixes` from pubid.

- **Canonical references only.** Relaton does not rewrite a non-canonical
  citation before it parses it: `I-D.draft-…`, `IETF RFC 8341`,
  `BIPM Metrologia …`, a W3C URL, `NIST … (IPD)` / `(January 2014)` /
  `NISTIR 8200:2018`, `JIS … (規格群)`, a lowercase `iec …`, an en dash — each
  gives no key and reaches the flavor's `get` as written, which normalizes it
  itself where it can (relaton#235). The canonical identifiers the data
  repos publish all parse as written (measured over every spec index fixture);
  pubid/pubid#463 and #464, which asked pubid to accept the other spellings,
  were closed for this.
- **References with one key must get one answer from the flavor.** pubid can
  read several spellings as one identifier (`doi:…`, `DOI:…` and a
  `https://doi.org/…` URL are one `Pubid::Doi` key). If the flavor's `get`
  answers only some of them, a miss on another spelling is cached as
  `not_found` under the shared key and poisons the canonical one for 60 days.
  So `Doi::Crossref.get` strips every such prefix. Check this whenever a
  flavor's routing or its pubid grammar changes.
- **Generated references must be canonical too.** `combine_doc` joins an ITU
  or NIST supplement with a space (`NIST SP 800-38A Add`), since pubid does not
  parse `NIST SP 800-38A/Add`.
- **A processor overrides `cache_pubid` only for policy**, not to normalize:
  Adobe, IANA, IEEE and ISBN read an unparseable reference as a miss, so their
  parse error means "no key"; IEC answers `IEV` with the vocabulary, so `IEV`
  gets no key.
- **A flavor parse error is a fallback, not a failure**: the query is not
  keyed, and the flavor's `get` receives the reference as written
  (`Core::Processor#cache_pubid` rescues to nil, with a log line; root
  `CLAUDE.md`, "A query reference the flavor's grammar cannot read falls
  back to the flavor as written").
- **The year goes where the flavor's `get` puts it.** The default
  `#fold_year` sets the identifier's own year; ISO, CEN and BSI apply a year
  to `#root` (the base document of a supplement, the adopted document of an
  adoption), so their processors use `#fold_year_on_root`. A flavor with no
  year component drops it, which matches their `get` (it ignores the year).
- **No key, no cache.** A processor with a pubid class that answers `nil` is
  not cached for that query: a flavor miss by the flavor's own rule (Adobe,
  IANA, IEEE, an incorrect ISBN, `IEV`) and a query whose answer the cache
  cannot hold (a CCSDS format, which filters the item's sources — CCSDS
  overrides `query_pubid`, so its `get` also receives the String; an OGC year,
  which is not the pubid's document-number year — OGC keeps that rule in
  `cache_key`, so its `get` still receives the pubid).
- **The publication date range is never in the key.** It selects among the
  cached editions (`Cache#candidates` + `pub_date_in_range?`); on a miss the
  flavor is asked with the range and the answer is cached under **its own**
  identifier only, so the undated query row keeps pointing to the latest
  edition. Bounds may be `YYYY`, `YYYY-MM` or `YYYY-MM-DD`.
- A processor with **no** pubid class (a third-party one) keeps the legacy
  string key from `std_id` (`ISO(ISO 19115-1:2014 (all parts))`).

## Testing

- Umbrella (Db) specs live in `spec/relaton/` and run from there (`rake spec:relaton`)
- RSpec with VCR cassettes in `spec/relaton/vcr_cassettes/` for recorded HTTP interactions
- Tests create `testcache`/`testcache2` directories and clean them in `before(:each)`.
  Assert cache contents through `Relaton::Db::Cache` (`#[]`, `#rows`, `#all`),
  not through file names: the store names its files itself.
- Cache-related tests need `<fetched>` elements in XML for `valid_entry?` to return true
- Integration tests in `spec/relaton/relaton_spec.rb`; unit tests under `spec/relaton/`
- **ISO lookups are stubbed, not cassette-recorded.** Flavor gems (relaton-iso/iec/nist)
  fetch a large live `index-v2` and deserialize every id through a pinned pubid build,
  so a single drifted id in the live index makes the whole index unparseable and ISO
  lookups return `nil`. Umbrella specs therefore stub `Relaton::Iso::Bibliography.get`
  (and other flavors' `.get`) to return hand-built `ItemData` — the umbrella's job is to
  test `Db` orchestration (`combine_doc`, caching, api fallback), not relaton-iso's index.
  Build stub items with the `docidentifier:` key (not `docid:`) so the id survives the
  cache XML round-trip. Don't reintroduce a live-index cassette for these.

## Style

- RuboCop config inherits from [Ribose OSS guides](https://github.com/riboseinc/oss-guides), target Ruby 3.3
- Each cache operation is atomic in lutaml-store (threads and processes). `Db`'s
  `@semaphore` (Mutex) only serializes its own check-then-act sequences across
  the two caches (validity check, clone, fetch-and-store).
