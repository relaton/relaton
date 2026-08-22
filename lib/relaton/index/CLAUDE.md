# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-index is a Ruby gem that provides indexing and searching of Relaton document references. It maps document identifiers to file paths, supporting both local index creation (for publishing) and remote index consumption (downloading from URLs with 24-hour caching).

## Commands

```bash
# Run all tests (default rake task)
rake spec

# Run linting
rake rubocop

# Run specific test file
bundle exec rspec spec/relaton/type_spec.rb

# Run specific test by name
bundle exec rspec spec/relaton/file_io_spec.rb -e "fetch_and_save"

# Install dependencies
bin/setup

# Interactive console
bin/console
```

## Architecture

### Core Classes (all under `Relaton::Index` module in `lib/relaton/index/`)

- **`Relaton::Index`** (module, `lib/relaton/index.rb`) — Static API entry point. Delegates to Pool and Config. Main methods: `find_or_create`, `close`, `configure`.

- **Pool** — Object pool that caches Type instances by document type (`:ISO`, `:IEC`, `:IHO`, etc.). Reuses existing indexes if parameters match, recreates if they change.

- **Type** — Represents one index for a document type. Holds an array of `{id:, file:}` hashes. Provides `add_or_update`, `search` (string substring match or block), and `save`.

- **FileIO** — Handles reading/writing/downloading index files. Three modes based on `@url`: string URL (download and cache to `~/.relaton/{type}/`), `true` (read local file from `~/.relaton/{type}/`), `nil` (read from current directory). Uses class-level Mutex for thread-safe downloads. Validates index format on load.

- **FileStorage** — Storage abstraction module with `ctime`, `read`, `write`, `remove`. Can be replaced via `Config.storage=` for custom backends (e.g., S3).

- **Config** — Global configuration: `storage`, `storage_dir`, `filename` (default: "index.yaml").

### Data Flow

1. `Relaton::Index.find_or_create(:TYPE, url:, file:, id_keys:, pubid_class:)` → Pool looks up or creates Type
2. Type lazily loads index via FileIO on first access
3. FileIO either reads local YAML or downloads ZIP from URL, extracts, validates format
4. Search matches against `:id` field (string comparison via `include?` or custom block)
5. `save` writes index as YAML to local file

### The narrowing key — one expression, six call sites

Search is two-stage: narrow, then match. Narrowing binary-searches the index for
the run of entries whose **base document number** equals the query's, using the key
`id.root.number.to_s` (`#root` walks a supplement/amendment `.base` chain, so a
document and its wrappers share one key and cluster together).

**Narrowing only happens for non-String queries** — `search_candidates` requires
`@file_io.sorted && id && !id.is_a?(String)`. A String query scans the whole index
*and* matches via `item[:id].to_s.include?(id)`, which renders every pubid in it.
So a flavor on a `pubid_class:` index must query with parsed identifiers; querying
it with strings is slower than the plain-string index it replaced.

That expression is written out in **six** places, and they must all agree or
bsearch silently returns the wrong slice:

| file | method | role |
|---|---|---|
| `type.rb:132` | `candidates_by_number` | the query's key |
| `type.rb:142` | `bsearch_left` | lower bound |
| `type.rb:148` | `bsearch_right` | upper bound |
| `file_io.rb:167` | `deserialize_pubid` | load-time sort |
| `file_io.rb:193` | `warn_unless_sorted` | sortedness check |
| `file_io.rb:278` | `sort_structured_index` | save-time sort |

**Consequence for pubid flavors:** once a flavor does query with parsed ids, an
identifier family whose `number` is nil keys every row to `""`, so they collapse
into one bucket and the bsearch buys nothing. It fails *silently* — results stay
correct, only speed drops. IETF Internet-Drafts are the worked example (see
`docs/data-repository-format.adoc`, "Two obligations a pubid-backed index
carries"); the fix belongs upstream, giving the family a real `number`, rather than
special-casing the key here.

### Index Format

YAML array of hashes with `:id` (string or structured hash) and `:file` (path string). Supports backward compatibility with old string-based format and newer pubid object format. The full data-repository/index specification (schema, `:id` v1/v2 shapes, publishing + GitHub Pages contract) lives in `docs/data-repository-format.adoc` at the repo root.

### Flavor `INDEXFILE` convention

Each flavor names its published index via a single constant in its top-level
`lib/relaton/<flavor>.rb`:

```ruby
INDEXFILE = "index-vN".freeze   # base name only — no extension
```

**Rules:**
- The constant is spelled **`INDEXFILE`** (one word, no underscore) and holds the
  **base name without extension** — `"index-v1"`, `"index-v2"`, etc.
- Call sites append the extension: `"#{INDEXFILE}.yaml"` for the local file passed
  as `file:`, `"#{INDEXFILE}.zip"` for the published artifact appended to the
  consumer `url:`. Never embed `.yaml`/`.zip` in the constant, and never hardcode
  `index-vN.zip` at a call site — derive it from `INDEXFILE` so a version bump is
  a one-line change.
- The version number encodes the index **structure** (`v1` = plain-string `:id`,
  `v2` = pubid-hash `:id`); bumping it lets the previous gem line keep reading the
  old file while the new structure is published under a new name.
- **Exception — jis** carries two constants (`INDEXFILE = "index-v1"` and
  `INDEXFILE_V2 = "index-v2"`) because it dual-writes both index generations during
  its pubid migration. Both still follow the no-extension rule.

### Key Design Decisions

- Remote indexes cached for 24 hours at `~/.relaton/{type}/index.yaml`
- Thread safety via `@@mutex` in FileIO prevents concurrent downloads of the same file
- Pubid deserialization is optional — when `pubid_class` is provided, string IDs are converted to structured objects
- Index format validation checks for required `:id` and `:file` keys, with automatic recovery (re-download or removal) on corruption
