# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the
`Relaton::Gost` flavor.

## Project Overview

`Relaton::Gost` retrieves **GOST** standards — the interstate/national standards of the
former-Soviet space (Государственный стандарт), published by Rosstandart and the
Euro-Asian Council for Standardization (EASC/МГС). It is **index-backed** (no scraping):
it searches a pre-built **pubid-structured** index via `Relaton::Index` and fetches
per-document YAML from the `relaton/relaton-data-gost` GitHub repo. The model layer mirrors
the `Relaton::Easc` sibling; the pubid-backed retrieval mirrors `Relaton::Oiml`.

## Architecture

Namespace: `Relaton::Gost`. Retrieval flow:

1. **Bibliography** (`bibliography.rb`) — `get(code, year, opts)` parses the citation with
   `Pubid::Gost.parse`, looks it up in the **pubid-structured** index, fetches the matching
   `row[:file]` YAML over `Net::HTTP` (`Item.from_yaml`, raising `Relaton::RequestError` on
   non-200), and stamps `fetched`. `search` picks the **latest edition** (`max_by { year }`)
   among number-matched candidates; `get` then strips the year for an **undated** citation via
   `to_most_recent_reference` (so `GOST 1.0` renders undated but resolves the newest edition),
   while a dated citation (`GOST 1.0-92`) or explicit `year` pins that edition. Mirrors
   `lib/relaton/oiml/bibliography.rb`.
2. **Index** — `Relaton::Index.find_or_create(:gost, url: "#{ENDPOINT}index-v2.zip",
   file: "index-v2.yaml", pubid_class: ::Pubid::Gost::Identifier)`. Each row's `:id` is a
   `_type: pubid:gost:{interstate,national}-standard` hash that `Relaton::Index` rebuilds into
   a `Pubid::Gost` identifier via `from_hash`; passing the parsed pubid to `#search` lets it
   binary-search candidates by number before the block runs `pubid_match?`. `INDEXFILE =
   "index-v2"` is in `lib/relaton/gost.rb`.
3. **Item / ItemData / Ext** (`item.rb`, `item_data.rb`, `ext.rb`) — `Item` extends
   `Bib::Item`, re-declares `ext` to the typed `Gost::Ext` and `docidentifier` to the pubid
   `Gost::Docidentifier`. `Ext`'s GOST fields (`urn`, `webpage`, `ics_code`, `developer`,
   `keywords` [collection], `pages`, `designation_original`) round-trip natively through YAML
   **and** XML (mapped in both `xml` and `key_value`). (The live dataset uses `urn`/`webpage`/
   `ics_code`/`pages`/`designation_original`; `developer`/`keywords` are declared but unused.)
4. **Doctype** (`doctype.rb`) — `TYPES = %w[interstate national preliminary methodological]`
   (GOST, GOST R, PST, OD categories). Carried in the inherited `content` attribute.
5. **Docidentifier** (`docidentifier.rb`) — wraps a `Pubid::Gost` identifier (`attr_reader
   :pubid`); `content=` re-parses to keep `@pubid` in sync, and `remove_date!` nil-s the pubid
   `year` and re-renders `content` (GOST carries the edition as `year`, not `date`) so
   `to_most_recent_reference` yields `GOST R 34.12`. Mirrors `Oiml::Docidentifier`.
6. **Processor** (`processor.rb`) — registry integration; `@short = :relaton_gost`,
   `@prefix = "GOST"`, `@idtype = "GOST"`, and `@defaultprefix = %r{^(?:GOST|ГОСТ)\b}` so **both
   the Latin `GOST` and Cyrillic `ГОСТ` surface forms route here** (the `\b` stops it swallowing
   longer tokens). `remove_index_file` passes the same `pubid_class`. Every method touching a
   flavor constant lazy-`require_relative`s `../gost` first (the lazy-registry invariant;
   `spec/relaton/lazy_loading_spec.rb` guards it).

There are no scrapers — everything comes from the curated index + GitHub YAML.

## Pubid

The flavor is **pubid-backed** via `Pubid::Gost` (metanorma/pubid#108), on the `pubid` `main`
branch the root `Gemfile` already pins (for JCGM). `pubid_match?` uses the idiomatic
`query.matches?(row_id, ignore: [:year])` for an undated citation (matches every edition
sharing subtype + number; interstate vs national and `1.1` vs `1.10` stay distinct because
`matches?` compares the full identifier) and an exact `matches?` for a dated one. This relies
on `Pubid::Gost#exclude(:year)` honouring GOST's `year` attribute — that pubid fix (base
`exclude` no longer *deletes* `:year` when mapping to `:date`) is what unblocked the idiom; an
older pubid where `exclude(:year)` no-ops would make undated lookups match nothing. The
`relaton-data-gost` `index-v2.yaml` was built with this **same** pubid, so the rows deserialize
(a mismatched pubid would make `Relaton::Index` reject the whole index — cf. the root
`CLAUDE.md` JCGM note). If the root `Gemfile` reverts the pubid pin to a release, that release
must carry both `Pubid::Gost` and the `exclude(:year)` fix.

## Dataset

`relaton/relaton-data-gost` is the live data repo behind `ENDPOINT` (a real pubid-structured
`index-v2.yaml` + `data/*.yaml`). The specs run fully offline against a small committed subset
(see Testing).

## Testing

`spec/gost/` — self-contained, run via `bundle exec rake spec:gost` (or `cd spec/gost &&
bundle exec rspec -I . .`). Coverage:

- `ext_spec.rb`, `item_spec.rb` — YAML round-trip of the typed ext fields.
- `bibliography_spec.rb` — retrieval against real records copied from `relaton-data-gost`:
  the pubid-structured index fixture `fixtures/index-v2.zip` is pre-loaded into the
  `Relaton::Index` pool in `before(:suite)` (with `pubid_class`), and `fixtures/data/*.yaml`
  are served by WebMock (`support/webmock.rb`) — **no live network**. Covers dated/undated/
  Cyrillic lookups, undated→latest-edition, year-pinning, not-found (`nil`), and non-200
  (`Relaton::RequestError`). Fixture docs: interstate `GOST 1.0` (editions 2015 + 92) and
  national `GOST R 34.12-2015`.
- `processor_spec.rb` — processor shape + Latin/Cyrillic prefix routing.

To refresh the fixture, copy the wanted rows from `relaton-data-gost/index-v2.yaml` into
`fixtures/index-v2.yaml`, re-zip it to `fixtures/index-v2.zip`, and copy the matching
`data/*.yaml` files.

There is **no RelaxNG grammar** for GOST and no XML-schema validation spec: the metanorma
document model (`metanorma-model-iso/grammars/`) defines no GOST grammar, so there is nothing
to copy into `grammar/` and nothing to validate `to_xml` against. This matches the sibling
`easc` flavor (also grammar-less). If an official GOST grammar is ever added upstream, copy the
`<flavor>{,-compile}.rng` pair into `grammar/` and add a Jing-validation spec then.
