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

**SDO org/logo store (`Relaton::Sdo`).** A **non-flavor** lazy component
(`lib/relaton/sdo/`, autoloaded like the flavors) that answers metanorma#346
(central logo store) and relaton-db#132 (abbreviation → org name). Public entry
point `Relaton.organization("ISO")` (delegates to `Sdo::Store.instance`, mirroring
the `Relaton.prefix_flavor` idiom) returns an org with `name`/`name(lang)` and
`logo_query`/`logo` over logo variants keyed by style/format/size. It has **no
processor and no `Db::Registry` entry** — consistent with the scope note in
`lib/relaton/db/CLAUDE.md` (org metadata stays out of the processors). It fetches
a single `index.yaml` manifest from the `relaton-data-sdo` data repo and caches it
under `~/.relaton/sdo` (reusing `Relaton::Index::FileStorage`). See
`lib/relaton/sdo/CLAUDE.md`.

**`Index::FileStorage#write` must be a binary write.** It caches raw `Net::HTTP`
bodies, which are `ASCII-8BIT` strings; it uses `File.binwrite` (not
`File.write(..., encoding: "UTF-8")`, which would *transcode* ASCII-8BIT→UTF-8 and
raise `Encoding::UndefinedConversionError` on any non-ASCII byte — e.g. the `\xC3`
in a French/Cyrillic org name). `read` decodes back as UTF-8, so a byte-verbatim
write round-trips for both ASCII and UTF-8 content. This was latent until
`Relaton::Sdo` cached the first index with non-ASCII names; don't reintroduce an
`encoding:` transcode on write.

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
`relaton`. Don't fold it in. Its `Gemfile` uses `gem "relaton", path: "../.."`,
so a fresh `bundle install` resolves `relaton` from `../..` (the single combined
gem). Its `Gemfile.lock` is **gitignored** (untracked), so a clean checkout has
none and `bundle install` regenerates a correct one. A leftover local lock with
`remote: ../relaton-<flavor>` entries is monorepo-era rot — delete it and
`bundle install` (that's what a stale `spec:cli` bundle-install failure means).

**JCGM flavor & temporary pubid pin.** `Relaton::Jcgm` (`lib/relaton/jcgm/`) is a
pubid-backed flavor split out of BIPM (JCGM records moved to their own
`relaton-data-jcgm` repo, stored as `_type: pubid:jcgm:{guide,gum-guide,amendment,
corrigendum,meeting}`). It needs the JCGM support (meetings, bare `GUM`/`VIM-N`
guides, the `Corrigendum` type, and the flattened compact `to_hash`) that lives on
pubid **`main`** but isn't in the released `2.0.0.pre.alpha.8` that
`relaton.gemspec` pins — so the root `Gemfile` **temporarily pins** `pubid` to
`git: …/pubid.git, branch: main`. This is the **same pubid that built the published
`relaton-data-jcgm` index**, so the flavor deserializes it (an older/mismatched
pubid would make `Relaton::Index` reject the whole index). Revert the pin to the
released `pubid ~> 2.0.0.pre.alpha.8` once these changes ship in a release. See
`lib/relaton/jcgm/CLAUDE.md`.

**Stale-pubid-lock trap.** Because that pin is a **git branch** and `Gemfile.lock`
is gitignored, the installed pubid is whatever a past `bundle install` froze —
and `bundle install` does **not** refloat an already-locked git source. A lock
left behind by an earlier session therefore keeps reproducing *old* pubid
rendering, producing IEEE/BIPM spec failures that don't reproduce on CI (which
resolves fresh). Before diagnosing any pubid-shaped rendering failure, check
`grep -A2 pubid.git Gemfile.lock` against `git ls-remote …/pubid.git main` and
run **`bundle update pubid`** (not `bundle install`). Only after that is a
failure worth treating as a code bug.

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

The **relaton-cli** suite is not part of the flavor run (separate gem, separate
bundle). `rake spec:cli` runs it from the repo root — it shells into
`gems/relaton-cli` under `Bundler.with_unbundled_env` (the `build_all` pattern),
does `bundle check || bundle install` (so it works on a fresh checkout), then
runs relaton-cli's own `rake spec`. `rake spec:all` runs the parallel flavor
suite and then `spec:cli`. Plain `rake spec` stays flavors-only.

- Umbrella (`Relaton::Db`) specs are in `spec/relaton/` directly (flattened — a
  cache-dir named `relaton` would otherwise collide with a `relaton/` subdir).
- **Umbrella specs test routing, not retrieval.** `spec/relaton/`'s job is that
  `Db#fetch` picks the right flavor processor and hands back that flavor's item,
  so they stub `Relaton::<Flavor>::Bibliography.get` and assert the returned
  class/docid. A flavor's own retrieval — index download, document fetch — is
  covered by `spec/<flavor>/`, which owns the fixtures for it. Don't drive an
  umbrella example through a real index/cassette: it duplicates flavor coverage
  and silently rots when the flavor moves. That is how `f7ae1d721` (BIPM
  `INDEXFILE` → `index-v2`) broke `db_spec.rb`'s "BIPM Meeting" example — its
  cassette still held the dead `index-v1.zip`, so VCR raised
  `UnhandledHTTPRequestError` even though nothing about routing had changed.
- **Cassettes are refreshed on purpose — never revert them.** Every
  `spec/<flavor>/support/vcr.rb` sets `re_record_interval: 7 * 24 * 3600` with
  `clean_outdated_http_interactions: true`, so a full run re-records anything
  older than a week against the live services. That is **deliberate**: periodic
  re-recording is how the suite notices that a data source changed its format.
  A `rake spec` that leaves hundreds of modified cassettes in the working tree is
  therefore normal and expected — **don't `git checkout` them, and don't pin
  cassettes to `record: :none`**, which would blind the suite to exactly the
  drift the interval exists to catch. When a refresh turns a spec red, the
  default assumption is that upstream moved and **this repo must be reconciled
  to it**, not that the cassette is wrong.
- **A 404 on a data-repo document usually means a stale cached index fixture.**
  The common way a refresh turns a suite red: `relaton-data-<flavor>` renamed its
  documents and republished its index, but the suite's **cached** index —
  `spec/<flavor>/fixtures/index-v*.zip`, a curated subset, present in ~28 suites —
  still names the old files, so the document fetch 404s and `Bibliography.search`
  returns nil (surfacing as a `NoMethodError on nil` at the assertion). The fix is
  to **refresh the cached index fixture from the live published `index-v*.zip`**;
  do not revert the cassette and do not re-point the spec at some other document.
  Copy the live row **wholesale** — the `:id:` shape drifts along with the
  filename, and it can change the reference string a spec has to query. Observed
  in `spec/ieee/`, where the corrigendum row moved from
  `data/ieee-std-p802-16-2004-d-5-cor1-2005.yaml` to
  `data/ieee-p802-16-d5-cor-1-2005.yaml` *and* its base id went from
  `_type: pubid:ieee:standard` (with `year`, `prefix: P`) to
  `_type: pubid:ieee:project-draft-identifier` (with `type: P`, no year).
- **The one thing that is not upstream drift: a recorded transport failure.** A
  cassette that captured a 429/5xx (typically an empty body) recorded no data at
  all, so there is nothing to reconcile — re-record it cleanly. `rake spec` runs
  the suites **in parallel** by default, which is how this happens: Crossref caps
  at 10 req/s with 3 concurrent connections, and a parallel full run tripped it,
  writing `429 Too Many Requests` into 8 `spec/doi` cassettes. Re-record a
  rate-limited flavor by running **that suite alone** (`cd spec/doi && bundle exec
  rspec -I . .`), never under parallel `rake spec`. Diagnostic shortcut:
  `git diff <cassette> | grep 'code:'` — a `200` → `4xx` flip is never a code
  regression.
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

**Node in the release env (relaton-cli frontend).** relaton-cli's `relaton index`
command ships a compiled Vue+Tailwind bundle built from `gems/relaton-cli/frontend/`.
`rake build_all` now runs `rake build_frontend` (`npm ci` + `vite build`) before
`gem build`, so the **release job must have Node available** (the built
`frontend/dist/*` is gitignored and packaged explicitly by the gemspec). If Node
is absent the gem builds without the bundle and `relaton index` raises
`FrontendAssets::BuildMissingError`. See `gems/relaton-cli/CLAUDE.md`.

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
- **Index-file constant.** A flavor that publishes an index names it with a single
  `INDEXFILE = "index-vN"` constant (one word, **no extension**) in its top-level
  `lib/relaton/<flavor>.rb`; call sites append `.yaml`/`.zip` (`"#{INDEXFILE}.yaml"`,
  `"#{INDEXFILE}.zip"`). Don't embed the extension in the constant or hardcode
  `index-vN.zip` at a call site. (jis is the one sanctioned exception — it carries
  both `INDEXFILE`/`INDEXFILE_V2` for its dual-write migration.) The BIPM flavor
  advanced its single `INDEXFILE` to the pubid `index-v2` (`_type: pubid:bipm:*`,
  built/read via `pubid_class: ::Pubid::Bipm::Identifier`); the legacy bespoke
  `index-v1` is no longer produced here — `relaton-data-bipm`'s crawler still
  emits it using the retained public `Relaton::Bipm::Id`. See
  `lib/relaton/bipm/CLAUDE.md`. **IANA** followed the same shape: its `INDEXFILE`
  is now the pubid `index-v2` (`_type: pubid:iana:registry`, via
  `pubid_class: ::Pubid::Iana::Identifier`), and `relaton-data-iana`'s crawler
  derives the legacy `index-v1` from it. IANA ids carry no document number, so
  the bsearch key `number` holds the **top-level registry slug** — it was empty
  before pubid `feat/iana-index-number`, which would have bucketed all 3405 rows
  together and silently degraded the search. See `lib/relaton/iana/CLAUDE.md`.
  The index schema
  and data-repo publishing/Pages contract are specified in
  `docs/data-repository-format.adoc`; see also `lib/relaton/index/CLAUDE.md`.
- Don't reintroduce per-flavor gems/gemspecs or the combined-build step — it's
  one gem now.
- Don't add `relaton-cli` as a runtime dep of `relaton`.
- Keep `VERSION` single-sourced in `lib/relaton/version.rb`.
- Scratch/one-off scripts go under `/tmp/`, not the project root.
```
