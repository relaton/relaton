# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-logger is the logging infrastructure for the Relaton family. It extends Ruby's stdlib `Logger` with a **logger pool** (named loggers), **per-logger level sets** (fine-grained filtering instead of a single threshold), pluggable formatters (string and JSON), and a GitHub-issue reporting channel for bulk-fetch error summaries. Flavor gems log through it (e.g. `Relaton::Bib::Util` extends it with a `PROGNAME`).

## Development

```bash
bundle exec rake        # default task → rspec
bundle exec rspec spec/relaton/logger/log_spec.rb   # single file
bundle exec rake rubocop  # lint (separate task)
```

## Architecture

Namespace: `Relaton::Logger`. Key classes in `lib/relaton/logger/`:

- **`Log`** (`log.rb`) — subclass of `::Logger`. Replaces the single severity threshold with a `levels` Set (`add_level`/`remove_level`); `Log#add` writes only when the severity is in `levels`. Each call accepts a `progname` and a `key:` keyword used by formatters.
- **`Pool`** (`pool.rb`) — a container of named loggers (`[:default]`, `[:file]`, …); logging calls fan out to every logger in the pool.
- **`Config`** (`config.rb`) — `Relaton.configure { |c| ... }` / `Relaton.configuration`; the default `Configuration` seeds a `Pool` with a `:default` stderr logger at levels info/warn/error/fatal.
- **Formatters** — `FormatterString` emits `[progname] SEVERITY: (key) message`; `FormatterJSON` emits a JSON line merging the call's keyword args.
- **`Channels::GhIssue`** (`channels/gh_issue.rb`) — accumulates de-duplicated log lines and opens a GitHub issue via the REST API on `close` (needs `GITHUB_TOKEN`; silently skips when unset or empty). Used by `Relaton::Core::DataFetcher` to report bulk-ingest errors.

### Entry point

`Relaton.logger_pool` returns the configured pool; `Relaton.logger_pool.info "msg"` broadcasts to all loggers, and `Relaton.logger_pool[:default]` accesses one by name.

## External dependencies

`logger ~> 1.6`.

## Testing

RSpec with SimpleCov; specs mirror the lib structure under `spec/relaton/logger/`.
