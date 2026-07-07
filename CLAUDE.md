# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A single Ruby gem, **`relaton`** — bibliographic references to technical
standards (ISO, IEC, IETF, NIST, IEEE, …). It bundles every standards-body
"flavor" in one gem: the `Relaton::Db` API (registry, cache), the shared model
layer, and ~29 flavor plugins. Flavor code is **loaded lazily** via `autoload`,
so `require "relaton"` and using `Relaton::Db` does not load every flavor at
startup — each loads on first use.

`relaton-cli` (the command-line interface) is the one **separate** gem; it lives
in `gems/relaton-cli/` and depends on `relaton`.

> History: this repo was previously a monorepo of ~35 separate gems under
> `gems/`, assembled into one gem at build time. It has since been **collapsed
> into a single gem** (one gemspec, one `lib/` tree, one `VERSION`). The
> per-gem upstream repos are snapshots; this repo is canonical.

## Layout

```
relaton.gemspec          # the one gemspec (union of all flavors' external deps)
lib/
├── relaton.rb           # entry point: autoload per flavor, then require relaton/db
└── relaton/
    ├── version.rb       # Relaton::VERSION — the single source of truth
    ├── db.rb, db/       # Relaton::Db API: registry, cache, workers pool
    ├── core/ bib/ index/ logger/   # shared infrastructure
    └── iso/ iec/ ietf/ … 3gpp/     # ~29 flavor plugins (Relaton::Iso, …)
spec/<flavor>/           # each flavor's spec suite (self-contained; see Testing)
grammar/                 # shared RelaxNG test schemas (test-only, not shipped)
gems/relaton-cli/        # the separate relaton-cli gem — the ONLY thing under gems/
```

`gems/` holds **only** `relaton-cli`. The old per-flavor `gems/relaton-<flavor>/`
dirs from the monorepo era are gone; if any reappear (as untracked SimpleCov
`coverage/`, `Gemfile.lock`, or `testcache/` leftovers) they're stale artifacts,
not source, and are safe to `rm -rf`.

## Common commands

```sh
bundle install
bundle exec rake spec              # run every flavor's spec suite
bundle exec rake spec:iso          # run one flavor's suite
bundle exec rake build             # build the relaton gem into pkg/
bundle exec rake build_all         # build relaton + relaton-cli
```

## Architecture: what's non-obvious

**Lazy registry.** `Relaton::Db::Registry#register_gems` requires only each
flavor's lightweight `relaton/<flavor>/processor` file — never the heavy flavor
top-level. A processor's class body references just `Relaton::Core::Processor`;
all flavor-heavy code (models, external deps) is lazy-`require_relative`d inside
its methods (`get`/`from_xml`/`from_yaml`/`grammar_hash`/`remove_index_file`).
So building a `Db` loads almost nothing. **Invariant:** any processor method
that touches a flavor constant (`INDEXFILE`, `Util`, a model class, `Digest`, …)
MUST `require_relative "../<flavor>"` (or the specific file) first — otherwise it
NameErrors on the cold path (reachable via `Db#fetch` → `Cache.grammar_hash` and
`Db#clear` → `remove_index_file`). `spec/relaton/lazy_loading_spec.rb` guards this.

**Autoload entry.** `lib/relaton.rb` declares `autoload :Iso, "relaton/iso"` per
flavor (3gpp → `ThreeGpp`). Referencing a flavor namespace before a `Db` is
built loads it on demand. When adding a flavor, add an autoload line here.

**Single `VERSION`.** `lib/relaton/version.rb` defines `Relaton::VERSION` — the
one version constant. There are **no** per-flavor `version.rb` files or
`Relaton::<Flavor>::VERSION` constants anymore: since this is one gem they'd all
be identical to `Relaton::VERSION`, so they were removed. Each flavor's
`grammar_hash` hashes `Relaton::VERSION` directly (`Digest::MD5.hexdigest
Relaton::VERSION`) for cache invalidation; bumping `Relaton::VERSION` re-stamps
them all. (`Relaton::Db::VERSION` in `lib/relaton/db/version.rb` is a separate,
independently-set constant, not part of this scheme.) **relaton-cli follows the
same source of truth:** its `Relaton::Cli::VERSION` is `Relaton::VERSION` (its
`version.rb` requires and re-exports it), and its gemspec reads the root
`version.rb` at build time to set `spec.version` and pin `relaton` **exactly**
(`= Relaton::VERSION`). So the release's single `gem bump` of the root file
re-stamps both gems in lockstep — nothing to hand-sync (see **Releasing**).

**Shared test grammars in `grammar/`.** The RelaxNG schemas specs validate XML
against live in one top-level `grammar/` (deduped from the old per-gem
`spec/schemas/`). Specs reference them as `Jing.new "../../grammar/<flavor>-compile.rng"`
(relative to the spec's CWD, which is `spec/<flavor>/` — two levels under root,
so `../../grammar` resolves to repo root). Co-located schemas keep the RelaxNG
`<include href="...">` chains working. Test-only; not in the gemspec.

**relaton-cli is separate.** `gems/relaton-cli/` is its own gem depending on
`relaton`. Don't fold it in. Its `Gemfile` uses `gem "relaton", path: "../.."`.

## Testing

Each flavor's specs live in `spec/<flavor>/` and run **self-contained** against
the single gem: `rake spec` does `cd spec/<flavor> && rspec -I . .` per flavor.
Running each in its own dir keeps their CWD-relative fixture/cassette paths,
`__dir__`-relative index fixtures, `../../grammar` refs, and per-flavor
`before(:suite)` index hooks working without a fragile flat merge (no constant
or VCR-config collisions across flavors). Each `spec/<flavor>/` has its own
`.rspec` (`--require spec_helper`).

`rake spec` runs the flavor suites **in parallel** across a bounded pool of
worker threads (each thread spawns one `bundle exec rspec` subprocess — the
suites are already OS-process-isolated per flavor, so there is no shared
in-memory state to collide, and the per-flavor CWD keeps their
cassette/`testcache`/`.rspec_status`/`Dir.mktmpdir` paths distinct). Default
pool size is `min(Etc.nprocessors, suite_count)`; override with `JOBS=N`, and
`JOBS=1` restores a strictly sequential run. Each suite's output is **captured**
(not streamed), and a one-line `PASS`/`FAIL` + example-count + timing status
prints as each suite *completes* (out of order under the pool; the print is
mutex-guarded so lines never interleave). It ends with a compact report: an
aggregate `N passed, M failed (K suites, T total)` line (`T` is the summed
per-suite time), the full output of *only* the failing suites grouped at the
bottom, a verdict line naming them, and a real `wall:` clock line (well under
`T` thanks to the parallelism). Set `VERBOSE=1` to also dump each suite's full
captured output as one grouped block when it finishes. `FLAVOR_SPECS` is
auto-derived from `spec/*/` dirs that contain a `*_spec.rb` (so non-suite dirs
like `spec/vcr_cassettes/` are skipped). The pool runner (`SpecReporter.run_suites`,
worker-must-not-raise contract), the `JOBS` resolver (`SpecReporter.job_count`),
and the report/parsing logic are the pure `SpecReporter` module in
`tasks/spec_reporter.rb` (top-level `tasks/` — test-only tooling, **not** shipped;
the gemspec globs only `lib/`), unit-tested by `spec/tasks/`. Per-flavor
`rake spec:<flavor>` tasks still stream live output single-threaded (unchanged).

- Umbrella (`Relaton::Db`) specs are in `spec/relaton/` directly (flattened — a
  cache-dir named `relaton` would otherwise collide with a `relaton/` subdir).
- **Known issue:** `spec/oiml/` marks 8 tests pending — `Pubid::Oiml::Identifier.from_hash`
  fails only inside the combined-gem bundle (a runtime-dep interaction; identical
  pubid/lutaml versions pass in isolation), so the OIML index can't deserialize.
  This is a real combined-gem bug surfaced by the full suite; needs a dependency
  bisect of the gemspec.

## Releasing

Both gems ship from `.github/workflows/release.yml` (manual **Actions → release
→ Run workflow**, or a `do-release` `repository_dispatch`). It delegates to the
shared `relaton/support` → `metanorma/ci` `rubygems-release.yml`: for a non-`skip`
`next_version` that job runs `gem bump --version <next> --tag --push` on the one
root `lib/relaton/version.rb`, then runs this repo's `release_command`
(`rake build_all` + `gem push` for **both** gems). Because relaton-cli derives
its version and its exact `relaton` pin from that same root file at build time
(see **Single `VERSION`**), one bump + one tag publishes `relaton` and
`relaton-cli` together at the same version — no per-gem version bump needed.

## Conventions to keep

- **Per-flavor docs.** Each flavor keeps its own `lib/relaton/<flavor>/CLAUDE.md`
  with that flavor's architecture notes (retrieval flow, key classes). These are
  dev docs — excluded from the packaged gem via the gemspec `files` glob.
- **Adding a flavor:** drop `lib/relaton/<flavor>/…` (with a `processor.rb`; the
  flavor's `grammar_hash` should hash `Relaton::VERSION` — don't add a per-flavor
  `version.rb`), add an `autoload` line to
  `lib/relaton.rb`, add the prefix to `Relaton::Db::Registry::SUPPORTED_GEMS`,
  add its external deps to `relaton.gemspec`, put `<flavor>(-compile).rng` in
  `grammar/`, add specs under `spec/<flavor>/`, and a `lib/relaton/<flavor>/CLAUDE.md`.
- Don't reintroduce per-flavor gems/gemspecs or the combined-build step — it's
  one gem now.
- Don't add `relaton-cli` as a runtime dep of `relaton`.
- Keep `VERSION` single-sourced in `lib/relaton/version.rb`.
- Scratch/one-off scripts go under `/tmp/`, not the project root.
```
