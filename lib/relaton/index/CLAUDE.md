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

- **Type** — Represents one index for a document type. Holds an array of `{id:, file:}` hashes. Provides `add_or_update`, `search` (subset match, string substring match, or block), and `save`.

- **FileIO** — Handles reading/writing/downloading index files. Three modes based on `@url`: string URL (download and cache to `~/.relaton/{type}/`), `true` (read local file from `~/.relaton/{type}/`), `nil` (read from current directory). Uses class-level Mutex for thread-safe downloads. Validates index format on load.

- **ShardSource** (`shard_source.rb`) — Reads the machine index on a data repo's Pages site (relaton#189): `index/manifest.json`, then the one `index/shard-NNNNN.json` at `Zlib.crc32(id.root.number.to_s) % shards`. Memory only, 24 h TTL, one `Mutex`. Built by `Type` when `find_or_create` gets `pages_url:`. Reuses `FileIO#deserialize_id`/`#deserialize_pubid` through a file-less `FileIO`.

- **FileStorage** — Storage abstraction module with `ctime`, `read`, `write`, `remove`. Can be replaced via `Config.storage=` for custom backends (e.g., S3).

- **Config** — Global configuration: `storage`, `storage_dir`, `filename` (default: "index.yaml").

### Data Flow

1. `Relaton::Index.find_or_create(:TYPE, url:, file:, pubid_class:, pages_url:)` → Pool looks up or creates Type (`id_keys:` is accepted for one release with a deprecation warning, then ignored)
2. Type lazily loads index via FileIO on first access
3. FileIO either reads local YAML or downloads ZIP from URL, extracts, validates format
4. Search matches against `:id` field (string comparison via `include?` or custom block)
5. `save` writes index as YAML to local file

With `pages_url:` (W3C, the #189 pilot) steps 2–3 change: a non-String query
goes to `ShardSource#rows` and reads one shard, and `Type#index` (a String query,
a block-only search) is `ShardSource#whole_index`, the `<index>.zip` that the
manifest names, read from the Pages site. No `FileIO#read`, no disk cache.

### What `#search` matches by default

Search is narrow, then match. The **match** step, for two identifiers, is
pubid's asymmetric subset match `id === item[:id]` (`Pubid::SubsetMatch`): the
query is the reference, and a component it leaves nil or empty matches any
value. That is what a search by reference means, so a flavor whose optional
components are true wildcards passes **no block** — OASIS, W3C, XSF, IALA,
OGC, ECMA, 3GPP, CalConnect, GOST and Plateau each call
`index.search(pubid)`. A component that a flavor reads as "none" when nil is
declared `subset_strict` in pubid (pubid#408), so `===` compares it exactly.

A nil is a wildcard here, not "the document has none". A caller that needs
**exact** equality says so with `search(id, exact: true)`, which selects the
rows with `item[:id] == id`. The binary-search narrowing still runs first.
These callers do:

| caller | why |
|---|---|
| `Relaton::Ccsds::HitCollection#rows` (edition branch) | pubid's CCSDS `suffix` is a wildcard, so `CCSDS 101.0-B-4` would also reach the historical `101.0-B-4-S` — 260 such pairs in the index fixture. (The omitted language reached the translations too, until pubid#408 made `language` `subset_strict`.) |
| `Relaton::Ietf::Scraper#fetch_doc` | a draft slug omits the version, so `draft-foo` would match every `draft-foo-NN` and `.first` would pick one — 20,513 such pairs in the first 40k fixture rows |
| `Relaton::Gost::Bibliography#rows` (dated citation) | a dated citation names one edition; it replaces the old `query.matches?(row)` with no ignore list, which is `==` |
| `Relaton::Plateau::HitCollection#find` (reference with an edition) | a reference with an edition names that one row, as the old `row[:id] == ref` block did |
| `Relaton::Oiml::Bibliography#best_row` (a Bulletin) | a Bulletin's year, issue and sequence are its locator, so `OIML Bulletin 1960` is the volume and not every article of 1960 |

A String query keeps the substring match it always had, in both directions;
with `exact: true` it is compared with `==`. A block is a custom predicate for
any other rule, and `search` raises `ArgumentError` if it gets both a block and
`exact: true`.

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

### What each flavor call site passes

A pubid flavor calls `find_or_create` from three places, and they do not need
the same arguments:

| call site | `url:` | `pubid_class:` |
|---|---|---|
| producer — `DataFetcher#index` | none (`file:` is CWD-relative) | **yes** — `FileIO#save` calls `to_hash` only for instances of it |
| consumer — `Bibliography`/`HitCollection#index` | the published `.zip` | **yes** — without it the rows stay raw hashes and `Type#search` stops narrowing |
| consumer on the Pages shards (W3C) | none; **`pages_url:`** | **yes** — a shard row is deserialized with it |
| delete — `Processor#remove_index_file` | **`true`** | **no** |

The delete path is `Type#remove_file` → `FileIO#remove` →
`FileStorage.remove(file)`. `FileIO#file` is built from `url`, the type's
directory and `file:` only, and the delete never reads or deserializes the
index, so `pubid_class:` has no effect on it. `url:` does: without it `file` is
the bare name, so a `Db#clear` on an empty pool deletes `./index-vN.yaml` in the
working directory and leaves `~/.relaton/<type>/` in place. OASIS shipped that
bug until `url: true` was added. `spec/index/relaton/type_spec.rb` and
`spec/oasis/relaton/oasis/processor_spec.rb` guard both facts.

### Key Design Decisions

- **The shard path does not fall back.** A shard 404 is "not found" (`[]`), a
  transport failure raises `Relaton::RequestError` so `Db#net_retry` retries it,
  and an unreadable manifest/shard raises `Relaton::Index::Error`. Falling back to
  the monolith would turn a Pages outage into a silent full download.
  `Relaton::RequestError` is declared in `lib/relaton/core/request_error.rb`
  (`Relaton::Core::RequestError` is an alias). `relaton/index` requires that one file,
  not all of `relaton/core` or `relaton/bib`.
- **`Type#actual?` compares `pages_url`.** Without it `Pool#type` would keep
  serving a zip-backed `Type` to a caller that asks for the shards, or the
  reverse. A spec fixture that seeds the pool must answer `actual?` for
  `pages_url:` as well (see `spec/w3c/support/webmock.rb`).
- **`Type#search` does not look at a loaded `@index` in shard mode.** A parsed
  query always goes to its shard, so the 24 h TTL applies; `@index`, once
  loaded, is not refreshed.
- Remote indexes cached for 24 hours at `~/.relaton/{type}/index.yaml`
- Thread safety via `@@mutex` in FileIO prevents concurrent downloads of the same file
- Pubid deserialization is optional — when `pubid_class` is provided, string IDs are converted to structured objects
- Index format validation checks for required `:id` and `:file` keys, with automatic recovery (re-download or removal) on corruption
