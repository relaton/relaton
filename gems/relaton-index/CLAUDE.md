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

### Index Format

YAML array of hashes with `:id` (string or structured hash) and `:file` (path string). Supports backward compatibility with old string-based format and newer pubid object format.

### Key Design Decisions

- Remote indexes cached for 24 hours at `~/.relaton/{type}/index.yaml`
- Thread safety via `@@mutex` in FileIO prevents concurrent downloads of the same file
- Pubid deserialization is optional — when `pubid_class` is provided, string IDs are converted to structured objects
- Index format validation checks for required `:id` and `:file` keys, with automatic recovery (re-download or removal) on corruption
