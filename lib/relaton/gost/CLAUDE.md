# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the
`Relaton::Gost` flavor.

## Project Overview

`Relaton::Gost` retrieves **GOST** standards — the interstate/national standards of the
former-Soviet space (Государственный стандарт), published by Rosstandart and the
Euro-Asian Council for Standardization (EASC/МГС). It is **index-backed** (no scraping):
it searches a pre-built index via `Relaton::Index` and fetches per-document YAML from the
`relaton/relaton-data-gost` GitHub repo. Sibling to `Relaton::Easc` — same model layer,
same structure.

## Architecture

Namespace: `Relaton::Gost`. Retrieval flow:

1. **Bibliography** (`bibliography.rb`) — `get(code, year, opts)` delegates to `search`,
   which looks the citation up in the index and fetches the matching `row[:file]` YAML over
   `Net::HTTP`, returning `Item.from_yaml` (raising `Relaton::RequestError` on non-200) and
   stamping `fetched`. **Plain-string (pubid-free) matching:** `index.search(text)` keys on
   the bare citation string, not a parsed identifier — see the pubid note below. Mirrors
   `lib/relaton/iala/bibliography.rb`.
2. **Index** — `Relaton::Index.find_or_create(:gost, url: "#{ENDPOINT}index-v2.zip",
   file: "index-v2.yaml")` (no `pubid_class`). `INDEXFILE = "index-v2"` is defined in
   `lib/relaton/gost.rb`.
3. **Item / ItemData / Ext** (`item.rb`, `item_data.rb`, `ext.rb`) — `Item` extends
   `Bib::Item` and re-declares `ext` to the typed `Gost::Ext`, whose GOST-specific fields
   (`urn`, `webpage`, `ics_code`, `developer`, `keywords` [collection], `pages`,
   `designation_original`) round-trip natively through YAML **and** XML (mapped in both the
   `xml` and `key_value` blocks) — no per-repo merge hacks.
4. **Doctype** (`doctype.rb`) — `TYPES = %w[interstate national preliminary methodological]`
   (GOST, GOST R, PST, OD categories). Carried in the inherited `content` attribute.
5. **Docidentifier** (`docidentifier.rb`) — a plain `Bib::Docidentifier`; the docid string is
   the canonical citation form. Subclassed so a future `Pubid::Gost` can hook in via `#pubid`
   without changing the public interface.
6. **Processor** (`processor.rb`) — registry integration; `@short = :relaton_gost`,
   `@prefix = "GOST"`, `@idtype = "GOST"`, and `@defaultprefix = %r{^(?:GOST|ГОСТ)}` so **both
   the Latin `GOST` and Cyrillic `ГОСТ` surface forms route here**. Every method that touches
   a flavor constant lazy-`require_relative`s `../gost` first (the lazy-registry invariant;
   `spec/relaton/lazy_loading_spec.rb` guards it).

There are no scrapers — everything comes from the curated index + GitHub YAML.

## Pubid status (temporary)

`Pubid::Gost` (metanorma/pubid#108) is **not yet in the bundle**, so retrieval matches on the
plain citation string and `Docidentifier` is a plain `Bib::Docidentifier`. Once #108 ships,
swap `Bibliography#index` to a `pubid_class:`-keyed index and match on parsed identifiers
(mirroring `lib/relaton/oiml/bibliography.rb`) — the public `get`/`search` interface stays the
same. No new gemspec deps are needed today.

## Dataset

`relaton/relaton-data-gost` is the (future) data repo behind `ENDPOINT`. Until it is
populated, live fetches return nothing; the specs are fully offline.

## Testing

`spec/gost/` — self-contained, run via `bundle exec rake spec:gost` (or `cd spec/gost &&
bundle exec rspec -I . .`). Coverage:

- `ext_spec.rb`, `item_spec.rb` — YAML round-trip of the typed ext fields.
- `bibliography_spec.rb` — retrieval, fully **WebMock-stubbed** (stubbed index + `Net::HTTP`);
  asserts a hit returns a populated `Gost::ItemData`, a miss returns `nil`, and a non-200
  raises `Relaton::RequestError`. **No live network.**
- `bibdata_spec.rb` — serializes `to_xml` and **Jing-validates** it against
  `../../grammar/relaton-gost-compile.rng`, then round-trips the ext elements back through XML.
- `processor_spec.rb` — processor shape + Latin/Cyrillic prefix routing.

The `grammar/relaton-gost{,-compile}.rng` pair extends the shared `BibDataExtensionType` with
the GOST ext elements and overrides `DocumentType` with the GOST vocabulary. Test-only — not
shipped in the gem (the gemspec `files` glob covers only `lib/`), like this doc.
