# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-core is the foundation gem every flavor plugin builds on. It provides the abstract **`Relaton::Core::Processor`** base class (the registry plug-in interface), the search primitives (`HitCollection`, `Hit`), a parallel-fetch thread pool (`WorkersPool`), the `DataFetcher` base for bulk ingest, and small parsing/utility mixins. It has no knowledge of any specific standards body.

## Development

```bash
bundle exec rake        # default task → rspec
bundle exec rspec spec/core/processor_spec.rb   # single file
bundle exec rubocop     # lint (rubocop-performance/-rake/-rspec)
```

## Architecture

Namespace: `Relaton::Core`. Key classes in `lib/relaton/core/`:

- **`Processor`** (`processor.rb`) — abstract base with the template methods every flavor implements: `get`, `fetch_data`, `from_xml`, `from_yaml`, `grammar_hash`, `threads`. Flavor processors subclass it and set `@short`/`@prefix`/`@defaultprefix`/`@datasets` in `initialize`.
- **`HitCollection`** (`hit_collection.rb`) — holds search results, delegates to an internal array, and uses `WorkersPool` to fetch items in parallel (4 workers by default). Uses `WeakRef` to avoid a circular reference back to its hits.
- **`Hit`** (`hit.rb`) — wraps one search result; its `item` is lazy-loaded on first access.
- **`DataFetcher`** (`data_fetcher.rb`) — abstract base for flavor bulk fetchers; provides `gh_issue` reporting (via `Relaton::Logger::Channels::GhIssue`), `output_file`, and `serialize` helpers.
- **`WorkersPool`** (`workers_pool.rb`) — `SizedQueue`-backed thread pool for parallel work.
- **Mixins** — `DateParser` (`parse_date` for "February 2012"/"2012-02-03"/etc.), `ArrayWrapper` (`array(x)` → always an Array), `HashKeysSymbolizer` (recursive string→symbol keys).

### How flavors consume it (important)

Every flavor's `Relaton::<Flavor>::Processor < Relaton::Core::Processor`. Because the umbrella registry now loads flavors lazily (only their `…/processor` file), any processor method that touches a flavor constant must `require_relative "../<flavor>"` first — see the root `CLAUDE.md` "Registry is lazy" note.

## External dependencies

`nokogiri ~> 1.16`, `psych ~> 5.2.0`, `relaton-logger ~> 2.2.0.pre.alpha.1`.

## Testing

RSpec with SimpleCov. Specs live under `spec/core/` and mirror the lib classes; `spec/support/` defines dummy processor/types for exercising the base classes.
