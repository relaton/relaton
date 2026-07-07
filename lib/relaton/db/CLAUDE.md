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

Scope note: only *prefixes* live here. Broader "SDO/organization metadata" (org
names — relaton-db#132; logos — metanorma#346) was deliberately kept **out** of
relaton proper, destined for a separate store/gem; don't add it to the processors.

### Db (lib/relaton/db.rb) — Main Public API

`Relaton::Db#fetch(ref, year, opts)` is the primary entry point. It:
1. Identifies the processor via Registry prefix matching
2. Handles combined references (`+` for derivedFrom, `,` for amendments) in `combine_doc`
3. Delegates to `check_bibliocache` which manages the dual-cache lookup and network fetch flow

`Relaton::Db#fetch_all(text, edition, year)` searches cached entries, filtering by text content (via `match_xml_text?`), edition, and/or year. Returns an array of deserialized bibliographic items from both local and global caches.

The dual-cache strategy uses a **global cache** (`~/.relaton/cache`) and an optional **local cache** (project-level). `check_bibliocache` checks local first, falls back to global, and syncs between them.

### DbCache (lib/relaton/db/cache.rb) — File-based Storage

Stores entries as files under `{dir}/{prefix}/{filename}.{ext}` (e.g., `testcache/iso/iso_19115-1.xml`). Key behaviors:
- Cache keys are wrapped like `ISO(ISO 19115-1:2014)` and converted to filenames via regex
- Entries can be XML, "not_found {date}", or "redirection {target_key}"
- Undated references expire after 60 days; dated ones persist indefinitely
- Version tracking per prefix directory invalidates cache when processor grammar changes
- File locking (`LOCK_EX`) for thread-safe concurrent writes

### WorkersPool (lib/relaton/db/workers_pool.rb)

Thread pool for `fetch_async`. Default 10 threads per processor, overridable via `RELATON_FETCH_PARALLEL` env var.

### Cache Key Format

`std_id` builds keys like `ISO(ISO 19115-1:2014 (all parts) after-2020-01-01)`. The filename regex in `db/cache.rb` uses `[^)]+` — suffixes use `-` not parentheses to avoid breaking it.

## Testing

- Umbrella (Db) specs live in `spec/relaton/` and run from there (`rake spec:relaton`)
- RSpec with VCR cassettes in `spec/relaton/vcr_cassettes/` for recorded HTTP interactions
- Tests create `testcache`/`testcache2` directories and clean them in `before(:each)`
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
- Thread safety via `@semaphore` (Mutex) around cache reads/writes in Db
