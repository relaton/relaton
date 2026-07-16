# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

`Relaton::Jcgm` retrieves **JCGM** (Joint Committee for Guides in Metrology)
publications — the metrology **guides/GUM/VIM** and the committee **meeting**
proceedings. It is **index-backed** (no scraping): a reference is parsed with
`Pubid::Jcgm`, matched against a pre-built index, and the matching per-document
YAML is fetched from the `relaton/relaton-data-jcgm` GitHub repo.

JCGM was previously served **inside the BIPM flavor** (its records lived under
`relaton-data-bipm`). It is now its own SDO/flavor: the BIPM flavor no longer
matches `JCGM` in its default-prefix, no longer parses JCGM ids, and no longer
harvests the `jcgm` dir.

## Architecture

Namespace `Relaton::Jcgm`; require path `relaton/jcgm`. Retrieval flow:

1. **Bibliography** (`bibliography.rb`) — `get`/`search`: parses the reference
   with `::Pubid::Jcgm.parse`, looks it up in the index, fetches the matching
   YAML over HTTP. `ENDPOINT` points at `relaton-data-jcgm`.
2. **Index** — `Relaton::Index.find_or_create(:jcgm, url:, file:, pubid_class:
   ::Pubid::Jcgm::Identifier)`. Because rows are stored as `Pubid::Jcgm`
   identifiers, the generated index carries the structured `_type:
   pubid:jcgm:{guide,gum-guide,amendment,meeting}` form (not BIPM's bespoke
   `{group,type,number,year}` hash). Matching uses `pubid_match?`/`stem`: the
   year-stripped stem plus an optional exact-year filter — guide editions
   (`200:2008` vs `200:2012`) differ only by year and the latest is chosen via
   `max_by(&:year)`; meetings differ by number, which stays in the stem.
3. **Model** (`item.rb`, `ext.rb`, `doctype.rb`, `structured_identifier.rb`,
   `docidentifier.rb`, …) — the records are **BIPM-shaped** (meetings are
   `type: proceedings` / `ext.doctype: meeting-report`; guides are `type:
   standard`), so the model mirrors `Relaton::Bipm`'s (a JCGM `Doctype`, a single
   `structuredidentifier`) rather than OIML's. `docidentifier.rb` is pubid-backed
   like OIML's. The bibliography/index *wiring* follows OIML; the *model* follows
   BIPM.
4. **Processor** (`processor.rb`) — `@prefix = "JCGM"`, `@defaultprefix =
   %r{^JCGM\s}`, `@pubid_flavor = :Jcgm` (prefixes sourced from
   `Pubid::Jcgm.prefixes`). Lazy-`require_relative`s `../jcgm` in its methods.
5. **DataFetcher** (`data_fetcher.rb`, `meetings_parser.rb`) — (re)builds the
   `relaton-data-jcgm` dataset. `fetch("bipm-data-outcomes")` harvests meeting
   proceedings from a local checkout of `metanorma/bipm-data-outcomes`'s
   `jcgm/meetings-{en,fr}` dirs (the JCGM-only slice of BIPM's
   `DataOutcomesParser`; JCGM has no sub-resolutions or parts). The curated
   guide/GUM/VIM records are **not** harvested — they are hand-maintained YAMLs
   in the data repo's top-level `static/` dir, so `relaton-data-jcgm`'s
   `crawler.rb` indexes them itself (like relaton-data-bipm's crawler) by looping
   `static/**` and calling the public, guarded `DataFetcher#add_to_index`. Rows
   are indexed via the `Pubid::Jcgm::Identifier` object (with `pubid_class:` on
   the index), so `Relaton::Index` sorts the index by id number on save and
   serialises each id to its `_type: pubid:jcgm:*` hash — the published index is
   already sorted (no "not sorted by id number" warning on consumer fetch).
   `add_to_index` **guards** each id: an unparseable one (the legacy `JCGM GUM` /
   `JCGM VIM-3` / `Corrigendum` records) is skipped with a warning rather than
   corrupting the whole index.

## The naive ordinal (11st / 12nd / 13rd)

Meeting docnumbers print the ordinal with a **naive last-digit rule** (1→st,
2→nd, 3→rd, else th) and **no** 11/12/13 teens exception, so the real records
read `JCGM 11st Meeting (2006)`, `12nd`, `13rd`. This matches the source data and
`Pubid::Jcgm::Identifiers::Meeting.ordinal`, so the printed form round-trips
through pubid. The DataFetcher delegates to `Meeting.ordinal` (single source of
truth) rather than re-implementing it. Any validation MUST expect `11st`, not
`11th`.

## Record types & the index guard

The five `Pubid::Jcgm` types the index carries: `pubid:jcgm:{guide, gum-guide,
amendment, corrigendum, meeting}`. The bare `GUM`/`VIM-N` records parse as
`guide`, and `JCGM 200:2008 Corrigendum` parses as `corrigendum` (whose hash
nests its `base` guide) — all on pubid **main** (see Dependencies). `Relaton::Index`
rejects the whole index if a single row fails `from_hash`, so
`DataFetcher#add_to_index` **guards** each id defensively and skips an unparseable
docnumber with a warning rather than corrupting the index. Every current JCGM
record parses; the guard protects against a future malformed one.

## Testing

RSpec with WebMock. The offline index fixture `spec/jcgm/fixtures/index-v1.zip`
is pre-loaded into the `Relaton::Index` pool in `before(:suite)`
(`spec/jcgm/support/webmock.rb`); per-document requests are served from
`spec/jcgm/fixtures/{data,static}/**`. `spec/jcgm/fixtures/bipm-data-outcomes/**`
holds minimal source fixtures for the DataFetcher spec (the real upstream is not
vendored). `spec/jcgm/relaton/jcgm/pubid_spec.rb` guards the naive ordinals and
the `_type` forms.

## Dependencies

`pubid` (umbrella gem, provides `Pubid::Jcgm`), `relaton-bib`, `relaton-index`,
`relaton-core`.

> **Temporary dependency pin:** the JCGM support (meetings, bare `GUM`/`VIM-N`
> guides, the `Corrigendum` type, and the flattened compact `to_hash`) lives on
> pubid **`main`**, not the released `2.0.0.pre.alpha.8` the gemspec pins, so the
> repo `Gemfile` pins `pubid` to `git: …/pubid.git, branch: main`. This is the
> same pubid that built the published `relaton-data-jcgm` index — a mismatched
> pubid would make `Relaton::Index` reject that index. Revert to the released
> pubid once these changes ship.
