# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-cli is a Ruby CLI tool for managing bibliographic references to standards (ISO, IEC, IETF, NIST, etc.). It provides commands to fetch, convert, and organize standards metadata in XML, YAML, BibTeX, and HTML formats. Part of the broader Relaton/Metanorma ecosystem.

## Common Commands

```bash
# Install dependencies
bundle install

# Run all tests
bundle exec rspec

# Run a single test file
bundle exec rspec spec/relaton/cli/command_spec.rb

# Run a specific test by line number
bundle exec rspec spec/relaton/cli/command_spec.rb:42

# Build the gem
bundle exec rake build

# Lint (RuboCop, inherits from Ribose OSS guide)
bundle exec rubocop
bundle exec rubocop -a  # auto-fix
```

## Architecture

### Entry Point & CLI Framework

The executable `exe/relaton` calls `Relaton::Cli.start(ARGV)` which routes to `Relaton::Cli::Command`, a Thor-based command class. Thor handles argument parsing, option definitions, and subcommand routing.

### Command Structure

- `lib/relaton/cli/command.rb` — Main Thor command class with top-level commands (fetch, extract, concatenate, split, yaml2xml, xml2yaml, xml2html, yaml2html, convert, fetch-data)
- `lib/relaton/cli/subcommand_collection.rb` — `relaton collection` subcommands (create, info, list, get, find, fetch, import, export)
- `lib/relaton/cli/subcommand_db.rb` — `relaton db` subcommands (create, mv, clear, fetch, fetch_all, doctype)

### Option Forwarding Pattern

`Command#fetch` and `SubcommandDb#fetch` use the shared `fetch_document` helper (in `Relaton::Cli` private methods at the bottom of `command.rb`). This helper transforms Thor's kebab-case option keys to snake_case symbols via `gsub("-", "_").to_sym` and splats them as `**dup_opts` to `Relaton.db.fetch` / `Relaton.db.fetch_std`. Adding a new Thor option to these commands automatically forwards it to the underlying library with no method changes needed.

`SubcommandCollection#fetch` calls `Relaton.db.fetch` directly (not through `fetch_document`), so new options must be explicitly forwarded there.

Current fetch options that use this pattern: `--no-cache`, `--all-parts`, `--keep-year`, `--publication-date-before`, `--publication-date-after`.

### Malformed-identifier handling (CLI is the friendly layer)

The `relaton` library **raises** `Parslet::ParseFailed` (from pubid's parser)
when a reference can't be parsed — it does not swallow it, so API consumers of
`Relaton::Db` handle it themselves. The **CLI** is the single place that turns
it into a user-facing message: `fetch_document` rescues `Parslet::ParseFailed`
(alongside `Relaton::RequestError`) and returns `"<code>" is not a recognized
standards identifier`, and `SubcommandCollection#fetch` — which bypasses
`fetch_document` — rescues it too, emitting the same message via `Util.error`.
The paths that actually reach pubid's parser are `relaton fetch` (→
`Db#fetch`/`#fetch_std` → `processor.get`) and `relaton collection fetch` (→
`Db#fetch`). `relaton db fetch` is a **cache-only** lookup (`fetch_db: true`
short-circuits `check_bibliocache` to a cache-key read via `std_id`, which is
plain string manipulation, never `processor.get`), so it never parses and can't
raise `Parslet::ParseFailed` — a malformed id there simply misses the cache and
prints "No matching bibliographic entry found". `command.rb` and
`subcommand_collection.rb` therefore `require "parslet"` at load time so the
constant resolves even when an unrelated exception (e.g. an `ArgumentError` from
`parse_date_option`) is the one propagating through the rescue chain.

### Core Data Classes

- `lib/relaton/bibdata.rb` — `Relaton::Bibdata` wraps `RelatonBib::BibliographicItem`, adding URL type handling and serialization to XML/YAML/Hash. Uses `method_missing` to delegate to the underlying bibitem.
- `lib/relaton/bibcollection.rb` — `Relaton::Bibcollection` represents a collection of bibliographic items with title/author/doctype metadata. Handles XML/YAML round-tripping.
- `lib/relaton/element_finder.rb` — Mixin providing XPath utilities with namespace handling.

### Converters (Template Method Pattern)

- `lib/relaton/cli/base_convertor.rb` — Abstract base defining the conversion flow (convert_and_write, write_to_file_collection)
- `lib/relaton/cli/xml_convertor.rb` — XML → YAML conversion
- `lib/relaton/cli/yaml_convertor.rb` — YAML → XML conversion (includes processor detection via doctype)
- `lib/relaton/cli/xml_to_html_renderer.rb` — Renders XML/YAML to HTML using Liquid templates from `templates/`

### Data index site generator (`relaton index`)

`relaton index [DATA-DIR]` builds the modern, browsable GitHub Pages index for
`relaton-data-<flavor>` repos (e.g. https://relaton.github.io/relaton-data-bipm/),
replacing the shared Jekyll theme (`relaton/jekyll-theme-relaton-data-index`) +
`relaton/support` `data-deploy.yml` build. Pieces:

**One delivery mode, sharded.** The shell carries **no document data** — only
branding, the inlined bundle, and five `data-*` scalars describing the shard
layout — so page weight is a function of what the reader opens, not of corpus
size. Everything else is fetched:

```
_site/index.html          ~110 KB regardless of corpus size
_site/search-0000.json …  summary records {r,c,t,s,d,u,l}, `--shard-size` each
_site/detail-0000.json …  the rich fields, `--detail-shard-size` each
```

Two scope decisions are baked in here; both were deliberate, and re-litigating
either without reading this will lead you back to a 150 MB page:

1. **Crawler-indexability was dropped as a requirement.** The old `embedded`/`dom`
   modes rendered one `.document` row per document precisely so crawlers could
   read the corpus; that is what made the page O(corpus). relaton/relaton#48
   listed it as an acceptance criterion, and it was given up knowingly — these
   are machine-data repos whose consumers are relaton fetchers, and the Pages
   site is a "what data is available" browser reached from the repo. Restoring it
   means paginated `page/N/index.html` shells, not un-sharding the data.
2. **Therefore the three `--mode`s collapsed to one.** `dom` existed *only* to be
   crawlable, and as a data channel `data-*` attributes are strictly worse than
   JSON (bigger, and lossy — 7 fields, no detail). `embedded`'s remaining
   advantage was `file://` self-containment, which a fetched sidecar had already
   given up. `static-json` was just "sharded, with one shard". `--mode` is
   **removed**, not deprecated; see the note at the end of this section.

- `lib/relaton/cli/index_site_generator.rb` — scans `DATA-DIR/**/*.{yaml,yml}`
  (default `./data`, skips `index-v*.yaml`) **plus an auto-detected sibling
  `static/` folder** (`STATIC_DIRNAME`, a sibling of `DATA-DIR` = `repo_root/static`;
  `--no-static`/`static: false` opts out), normalizes each doc, and writes the
  shell plus the shards into `--output` (default `_site`).
  Both source dirs go through the same `SKIP_BASENAMES`/`document?` filters. De-dup
  is **cross-folder only**: `data/` is scanned first, so a `static/` doc whose
  normalized id already appeared in `data/` is skipped with a warning (data wins);
  duplicates *within* a single folder are left as-is (preserving the pre-static
  data-scan behavior), and a blank/empty normalized id never de-dups (so docid-less
  title-only docs aren't collapsed). Static docs get correct `static/<path>`
  raw-YAML links for free because `relative_path` is taken from `repo_root` (the
  parent of both `data/` and `static/`). `static/` holds manually-curated bib
  records the crawler can't fetch (ISO/IEC Directives, JCGM/GUM guides, NIST
  research-library metadata) that are already part of the corpus (in `index-vN.yaml`).
  **`each_document` is the streaming spine**: it yields normalized items instead
  of accumulating them, and `ShardWriter` buffers at most one shard of each
  family, so peak RSS is O(shard size) — measured at ~38 MB above baseline for a
  20,000-document, 79 MB corpus. Nothing may reintroduce a `collect_documents`
  that materializes the corpus; a spec asserts it is never called.
  **`purge_stale!` is load-bearing, not hygiene**: with no manifest, a
  `search-0034.json` left by a previous larger corpus is invisible (the shard
  count on the mount node says 34), so it would sit in the deployed site forever.
  **Per-flavor branding** beyond `--title` is
  `--description` and `--favicon` (both `nil` by default — the per-flavor values the
  deleted Jekyll `_config.yml`s carried, now supplied by the caller workflow). The
  description becomes `<meta name="description">` and `data-description` on the
  mount node; the favicon becomes `<link rel="icon">`
  with its href passed through **verbatim** and a `type` sniffed from the extension
  via `FAVICON_TYPES` (unknown extension → no `type`, the browser sniffs). The
  generator copies **no assets** (only the shell + the shards), so a relative
  favicon href is the caller's job to place in the deployed site — normally it's an
  absolute URL. Both tags are emitted by `{%- if … %}` branches in `page.liquid`, so
  a build with neither option is byte-identical to one that never had them —
  `spec/index_fixtures/golden/index.html` pins the whole shell, so regenerate it
  deliberately and read the diff when you touch that template.
  `title`/`description`/`favicon` all go
  through `presence`, which maps a blank string to `nil`: the deploy workflow
  forwards unset inputs as `--favicon ""`, and an empty `href` would make the
  browser re-fetch the page as its own icon.
- `lib/relaton/cli/index_item_normalizer.rb` — doc-hash → `{id,title,doctype,
  stage,date,link,yaml}` (the always-present summary core) **plus optional
  detail-page fields** (`abstract, edition, languages, keywords, publisher,
  contributors, docids, dates`) added by `details`. Reads the doc's own rendered
  fields (primary `docidentifier`, main/en `title`, `date[].at|on` preferring
  `published`, `ext.doctype`), so **no pubid reconstruction** is needed. Detail
  fields are dropped when empty (via `reject`), so a summary-only doc keeps the
  compact 7-key shape. The generator then splits that one record in two:
  `compact_record` projects the seven summary keys (renamed `r,c,t,s,d,u,l`) into
  the search shards, and `detail_record` takes **everything else**, tagged with
  `r`. The split is defined by one constant, `COMPACT_KEYS` — a key that isn't in
  it is a detail field by definition, so a new normalizer field lands in the
  detail shards automatically and never silently bloats the summary. The frontend
  `types.ts` `IndexDocument` / `DetailRecord` interfaces mirror both halves.

  **Detail lookup is positional, verified by id.** A detail shard is a *dense*
  array: slot `i` is either `null` (that document has no detail fields) or
  `{"r": "<id>", …}`. A `null` slot is still written, because the frontend finds a
  document's detail by arithmetic — `shard = ⌊i / detailShardSize⌋`,
  `slot = i % detailShardSize`, where `i` is its position in the corpus — and
  dropping empties would shift everything after it. Nothing stores that mapping,
  which is why `loadDetail` checks the entry's `r` against the document id and
  falls back to scanning the shard on mismatch: showing another document's
  abstract would be worse than showing none. Keep the two families written from
  the same single pass over `each_document`, or the arithmetic stops holding.

  **Corpus position is carried, never derived from the array index.** The shard
  loader stamps `pos` onto each document from its shard number
  (`i * shardSize + j`), and `App.vue` uses `doc.pos` — falling back to `indexOf`
  only for a document list supplied whole. This is not redundancy. A summary
  shard that fails to load leaves a *hole*: every later document then sits at an
  array index `shardSize` lower than its true position, which at the defaults
  (5000 / 500) addresses a detail shard **ten files early**. The `r` check would
  reject the wrong record, but its fallback scans only the shard it was sent to,
  so it can never recover a cross-shard drift — the failure would be silent
  summary-only detail panels for the entire rest of the corpus. Don't "simplify"
  `doc.pos` back to `indexOf`.
- `lib/relaton/cli/frontend_assets.rb` — reads the compiled bundle from
  `frontend/dist/` (one relative path works for both gem and git checkout);
  raises `BuildMissingError` with a "run `rake build_frontend`" message if absent.
  `dist_dir` is overridable so specs point at a fixture dist (no Node build).
- `templates/index/page.liquid` — the whole output HTML: head/branding, the
  inlined IIFE + CSS, and the mount node carrying the five shard scalars
  (`data-total`, `data-shards`, `data-shard-size`, `data-detail-shards`,
  `data-detail-shard-size`). Those attributes are the **only** description of the
  index's shape — there is deliberately no manifest file, which saves a
  round-trip before the first shard can be requested and removes a failure mode
  where the manifest 404s but the shards are fine. Shard file names are derived by
  convention on both sides (`search-%04d.json` / `detail-%04d.json`) and resolve
  relative to the page, which sits beside them. Rendered via a Liquid
  `Environment` (not the deprecated global `Template.file_system=`).
  (`_document.liquid` is gone with the crawler DOM.)
- `--flavor <f>` / `--repo <org/name>` shallow-clone the data repo to a tempdir
  and read its `data/`; the checked-out branch is auto-detected (bipm's is `v2`)
  and used for the raw-YAML `--base-url`. Default (no flavor/repo) reads the local
  folder — the in-Action path where the repo is already checked out.

**Frontend (`frontend/`).** A Vite 8 **library-mode** project
(`@vitejs/plugin-vue` + `@tailwindcss/vite` + Vue 3) that builds ONE
`frontend/dist/app.iife.js` + `style.css` (the lutaml-xsd embedding pattern,
modernized). `src/` is committed; `dist/` + `node_modules/` are gitignored and
built at package time. The island (`src/App.vue`) does search / doctype+stage
facets / sort / list-grid / dark-mode / copy-DocID / client pagination.

**Hydration is one synchronous path.** `src/lib/hydrate.ts` `resolveIndex(el)`
just reads the mount node — branding plus `readShardInfo` — and returns an empty
document list; there is nothing to await, so the app paints immediately and the
first shard request starts at boot. `src/lib/shards.ts` then owns all fetching:

- `loadSearchShards(info, onBatch)` — a bounded worker pool (4) over the summary
  shards. Two properties are load-bearing. **Order**: records are appended in
  shard order no matter what order responses arrive in, because corpus position is
  what the detail lookup is keyed to — a shard that resolves early waits for its
  predecessors. **Throttling**: `App.vue` re-filters and re-sorts the entire array
  on every change, so emitting per shard would re-sort a growing 166k-element
  array dozens of times; emissions are coalesced into one per `flushMs` window,
  with a forced final emit. A shard that 404s becomes `[]` rather than aborting
  the load, and `res.ok` is checked because a 404 on Pages returns an HTML error
  page that would otherwise throw inside `res.json()`.
- `createDetailLoader(info)` — fetch-on-open with a per-shard cache, so paging
  through neighbouring documents costs one request rather than one per document;
  concurrent opens in the same shard share a single in-flight promise.

`src/app.ts` holds `reactive()` `IndexData` and `Hydration` objects and mutates
them as shards land — `createApp(App, props)` props are **static**, so reassigning
a prop would never reach the component. The shard load is kicked off via
`requestIdleCallback` so it stays off the first paint.
The site `description` comes from `data-description` on the mount node; `App.vue`
renders it as the header subtitle, falling back to the default "Please use the
provided Relaton DocID…" sentence.

**The loading gates are the subtle part.** While shards are arriving the corpus is
knowingly incomplete, so anything that reads "absent" as "does not exist" has to
wait for `hydration.loading` to clear:
- an unresolved `?doc=` must **not** bounce to the list (that watcher previously
  treated not-found as removed-document; on a large index every deep link would
  break) — instead it calls `requestAll()` to hurry the load, and only drops the
  param once loading finishes;
- `?page=N` must not be clamped against a `pageCount` computed from a partial
  corpus — `clampPage()` is deferred to a `watch(loading)`, and `onPopState`
  skips clamping while loading;
- the count line reads `hydration.total` (known up front from `data-total`) so it
  says "12 of 166658", not a denominator that grows.
The `hydration` and `loadDetail` props are **optional**: mounted without them the
component behaves exactly as it did before, which is what keeps the pre-existing
tests meaningful.
Pagination is **viewport-adaptive**: `computePageSize()`
sizes a page from the available height and grid/list row density (recomputed on
resize — debounced — and on view-mode change, clamped `10..100`) rather than a
fixed 100 rows, and the Prev/Next/page controls live in a shared
`src/components/Pagination.vue` rendered **both above and below** the list. The
URL-synced state is **two params**, both in `src/lib/url.ts` (History API,
preserving each other + any other params, synced back by the `popstate`
listener): the current page `?page=N` (page 1 omits it —
`readPageFromUrl`/`writePageToUrl`) and the open **detail document** `?doc=<id>`
(`readDocFromUrl`/`writeDocToUrl`) so a reload/share/bookmark restores it. User
paging and opening/closing a detail use `history.pushState` (Back/Forward walk
pages and in/out of the detail), while restore-clamp and filter-reset use
`replaceState`. Search/facets/sort stay in-memory (view/theme still use the
`localStorage` `relaton-index-*` keys).

**Detail page.** Clicking a `DocumentRow` (its id/title/chevron — real
`?doc=<id>` anchors, click-intercepted to SPA-navigate) opens
`src/components/DocumentDetail.vue` in place of the list (`App.vue` swaps on the
`selectedDoc` computed; an unknown `?doc=` falls back to the list). It renders the
enriched fields (abstract, metadata grid, keywords, contributors, all identifiers,
all dates) and the landing + raw-YAML links, each block shown only when present so
a summary-only doc degrades gracefully. Pure
filter/sort logic is `src/lib/filter.ts`. UI icons
are inline Heroicons-outline SVGs via the shared `src/components/Icon.vue`
(`<Icon name="…" />`, a name→path map — `fill=none stroke=currentColor` so they
inherit text colour + dark mode), matching the CalConnect standards site — **not**
Unicode emoji; add a new glyph to `Icon.vue`'s `PATHS` rather than inlining an
emoji. Tests: `npm run typecheck` + `vitest`
(filter/hydrate/shards/url/App/Icon/DocumentDetail via happy-dom).
Anything touching the shard loaders needs a `fetch` stub — `src/test/fetch.ts`
(`stubFetch` + `deferred`) is the shared one; `deferred` is how the
out-of-order-response ordering test forces shard 1 to resolve before shard 0.

**`npm run dev`.** `src/dev/main.ts` shards `sample-data.json` in memory, stubs
`fetch` to serve it, and sets the mount-node scalars — i.e. the dev harness goes
through the *real* hydration path rather than a shortcut that only exists there.
Its shard sizes are deliberately tiny (3 / 2) so progressive loading is visible.

**Build wiring.** `rake build_frontend` (`npm ci`/`install` + `npm run build`) is
a prerequisite of `build`/`release`; the root `rake build_all` runs it before
`gem build`. The gemspec ships the gitignored `frontend/dist/*` explicitly
(`git ls-files` can't see it) and excludes the tracked `frontend/` sources.
**Release note:** the release pipeline must have Node available or the gem ships
without the bundle. The reusable Pages-deploy workflow (install relaton-cli →
`relaton index` → deploy-pages) belongs in `relaton/support` — data repos call it
via `uses: relaton/support/.github/workflows/data-deploy.yml@main` — not in this
repo (a reusable workflow only runs from the calling repo's `.github/workflows/`,
and an in-tree copy would also get packaged into the gem).

**`--mode` removal and the caller contract.** `--mode` is **gone**, not
deprecated. `relaton/support`'s `data-deploy.yml` passed it at two call sites,
and every `relaton-data-*` caller runs `source: git` — building relaton-cli from
`relaton/relaton` **main**, not a released gem — so there is no release gate:
a stale caller breaks on its next deploy run, not at some later `gem push`.
`/work/HANDOFFS/relaton__support__data-deploy-drop-mode-input.md` asks support to
drop the input, and **must land first**.

That is also why `Command.exit_on_failure?` now returns `true`. Thor's legacy
default is to print a usage error and exit **0**, so a caller passing the removed
flag would write no site at all and still go green — publishing an empty index
across ~29 unattended Pages deploys with nothing red. An acceptance spec pins the
loud failure. Don't remove `exit_on_failure?` to quiet a test.

**Don't pre-compress the shards, and don't add a single archive.** GitHub Pages
already gzips them in transit (measured: a 32.9 MB `search.json` transfers in
4.8 MB, and the old 151 MB 3gpp page in 6.4 MB — the hand-off's headline byte
counts were `curl` *without* `--compressed`, i.e. uncompressed sizes). Storing
`.json.gz` would be served as `application/gzip` with no `Content-Encoding`, so
the browser would not inflate it transparently: you would add a decompressor to
the bundle to reach bytes Fastly already gives you, and forfeit brotli. A single
zip (the `index-vN.zip` pattern the data repos use for their *machine* index) is
worse still here — nothing renders until all of it arrives, which is exactly the
O(corpus) first paint this design removes. The real remaining cost was never
transfer; it is parse/DOM/heap, which compression does nothing for.

**Known ceiling.** Sharding fixes *transfer and parse*, not *compute*. 166k
documents is still ~40–60 MB of JS heap, and `applyFilters` runs a full
`Intl.Collator` sort over the whole array on every keystroke. The real fix is a
prebuilt inverted index or server-side search; that is a separate design, not
something to bolt onto the shard loader.

### File Operations

`lib/relaton/cli/relaton_file.rb` — Static methods for extract (pull bibdata from Metanorma XML), concatenate (combine files into a collection), and split (break a collection into individual files).

### Database (Singleton)

`Relaton::Cli::RelatonDb` (in `lib/relaton/cli.rb`) is a Singleton managing a `Relaton::Db` instance. DB path is persisted in `~/.relaton/dbpath`. The `relaton` gem's registry auto-discovers 30+ standard-body processors.

### Processor Detection

`Relaton::Cli.processor(doc)` and `.parse_xml(doc)` detect the correct processor (ISO, IEC, IETF, etc.) from a document's `docidentifier` element type attribute, falling back to prefix matching.

## Test Structure

- `spec/acceptance/` — End-to-end CLI integration tests using `rspec-command`
- `spec/relaton/cli/` — Unit tests for command, converters, subcommands, DB
- `spec/relaton/` — Unit tests for Bibcollection and Bibdata
- `spec/support/` — Test setup: SimpleCov, WebMock, VCR, equivalent-xml matchers
- `spec/fixtures/` and `spec/vcr_cassettes/` — Test data and recorded HTTP responses

Tests use VCR cassettes to replay HTTP interactions with standards registries. WebMock blocks real HTTP requests in tests.

## Key Dependencies

- `relaton` — Core library providing DB, registry, and all standard-body
  processors. relaton-cli releases in lockstep with it: both the gemspec pin
  (`= <version>`) and `Relaton::Cli::VERSION` derive from the root
  `lib/relaton/version.rb` (`Relaton::VERSION`), so they never drift apart.
- `thor` / `thor-hollaback` — CLI framework
- `liquid ~> 5` — HTML template rendering
- `nokogiri` (transitive via relaton) — XML parsing

## Ruby Version

Requires Ruby >= 3.0.0 (set in gemspec and `.rubocop.yml`).
