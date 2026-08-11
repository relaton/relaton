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

- `lib/relaton/cli/index_site_generator.rb` — scans `DATA-DIR/**/*.{yaml,yml}`
  (default `./data`, skips `index-v*.yaml`) **plus an auto-detected sibling
  `static/` folder** (`STATIC_DIRNAME`, a sibling of `DATA-DIR` = `repo_root/static`;
  `--no-static`/`static: false` opts out), normalizes each doc, and renders a
  self-contained `index.html` + `search.json` into `--output` (default `_site`).
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
  Three `--mode`s: `embedded` (crawler DOM + `window.RELATON_INDEX_DATA` JSON —
  default), `dom` (crawler DOM only), `static-json` (`search.json` sidecar,
  fetched; not crawlable). JSON is `script_escape`d (`</`→`<\/`, U+2028/9) so it
  can't break out of the `<script>`. **Per-flavor branding** beyond `--title` is
  `--description` and `--favicon` (both `nil` by default — the per-flavor values the
  deleted Jekyll `_config.yml`s carried, now supplied by the caller workflow). The
  description becomes `<meta name="description">`, `data-description` on the mount
  node **and** a `description` key in the embedded payload (added only when set, so
  an unbranded site's JSON is unchanged); the favicon becomes `<link rel="icon">`
  with its href passed through **verbatim** and a `type` sniffed from the extension
  via `FAVICON_TYPES` (unknown extension → no `type`, the browser sniffs). The
  generator copies **no assets** (only `index.html` + `search.json`), so a relative
  favicon href is the caller's job to place in the deployed site — normally it's an
  absolute URL. Both tags are emitted by `{%- if … %}` branches in `page.liquid`, so
  a build with neither option is **byte-identical** to before they existed — keep it
  that way when touching that template. `title`/`description`/`favicon` all go
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
  compact 7-key shape. They ride **only** in the embedded `window.RELATON_INDEX_DATA`
  payload: `search_json` projects only the compact summary keys and the crawler
  `_document.liquid` DOM carries only summary `data-*` attributes, so `dom` /
  `static-json` builds stay lean and the detail page falls back to summary+links
  there. The frontend `types.ts` `IndexDocument` interface mirrors this contract.
- `lib/relaton/cli/frontend_assets.rb` — reads the compiled bundle from
  `frontend/dist/` (one relative path works for both gem and git checkout);
  raises `BuildMissingError` with a "run `rake build_frontend`" message if absent.
  `dist_dir` is overridable so specs point at a fixture dist (no Node build).
- `templates/index/{page.liquid,_document.liquid}` — the page shell (inlines the
  IIFE + CSS + JSON) and the crawler-indexable `.document` row (data-* attributes
  the frontend hydrates from). Rendered via a Liquid `Environment` (not the
  deprecated global `Template.file_system=`).
- `--flavor <f>` / `--repo <org/name>` shallow-clone the data repo to a tempdir
  and read its `data/`; the checked-out branch is auto-detected (bipm's is `v2`)
  and used for the raw-YAML `--base-url`. Default (no flavor/repo) reads the local
  folder — the in-Action path where the repo is already checked out.

**Frontend (`frontend/`).** A Vite 8 **library-mode** project
(`@vitejs/plugin-vue` + `@tailwindcss/vite` + Vue 3) that builds ONE
`frontend/dist/app.iife.js` + `style.css` (the lutaml-xsd embedding pattern,
modernized). `src/` is committed; `dist/` + `node_modules/` are gitignored and
built at package time. The island (`src/App.vue`) does search / doctype+stage
facets / sort / list-grid / dark-mode / copy-DocID / client pagination, hydrating
from `window.RELATON_INDEX_DATA`, the crawler DOM, or a fetched `search.json`
(`src/lib/hydrate.ts`). All three paths also resolve the site `description`
(`IndexData.description`): the embedded payload's value wins, otherwise
`pageDescription(el)` reads `data-description` off the mount node — so `dom` and
`static-json` builds get it too. `App.vue` renders it as the header subtitle,
falling back to the default "Please use the provided Relaton DocID…" sentence.
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
emoji. Tests: `npm run typecheck` + `vitest` (filter/hydrate/url/App/Icon/DocumentDetail via happy-dom).

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
