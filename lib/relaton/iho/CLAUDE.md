# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

relaton-iho is a Ruby gem that fetches and serializes IHO (International Hydrographic Organization) standards metadata. It is a "flavor" gem in the Relaton ecosystem, extending relaton-bib with IHO-specific bibliographic data models.

## Common Commands

```bash
bundle exec rspec                        # run all tests
bundle exec rspec spec/relaton/iho/item_spec.rb  # run a single spec file
bundle exec rspec spec/relaton/iho/item_spec.rb:15  # run a single example by line
bundle exec rubocop                      # lint
bundle exec rubocop -a                   # lint with auto-fix
bundle exec rake install                 # install gem locally
```

## Architecture

### Flavor Pattern

This gem follows the Relaton flavor pattern: it subclasses base classes from `relaton-bib` under the `Relaton::Iho` namespace. The key mechanism is `NamespaceHelper` (from relaton-bib), which dynamically resolves the module namespace from the class name. This means `Relaton::Iho::ItemData#to_xml` automatically delegates to `Relaton::Iho::Bibdata.to_xml` (not `Relaton::Bib::Bibdata`).

Core model classes and their base classes:
- `Item < Bib::Item` — main bibliographic item, uses `model ItemData`
- `ItemData < Bib::ItemData` — data container enabling namespace-aware `to_xml`/`to_yaml`/`to_json`
- `ItemBase < Item` — stripped-down item for use inside relations (no id, schema_version, fetched, ext)
- `Bibitem < Item` — XML bibitem serialization (includes `Bib::BibitemShared`)
- `Bibdata < Item` — XML bibdata serialization (includes `Bib::BibdataShared`)
- `Relation < Bib::Relation` — overrides `bibitem` attribute to use `Iho::ItemBase`
- `Doctype < Bib::Doctype` — IHO document type vocabulary
- `Ext < Bib::Ext` — IHO-specific extension data (doctype, commentperiod)
- `Processor < Core::Processor` — Relaton processor for registry integration
- `HashParserV1` — converts v1-format YAML/Hash data to v2 model objects (required on demand, not auto-loaded)
- `Bibliography` — fetches IHO data from relaton-data-iho GitHub repo

All model classes use Lutaml::Model for declarative attribute/serialization definitions.

### HashParserV1

`HashParserV1` (in `hash_parser_v1.rb`) handles conversion of legacy v1 data to the current model. It overrides the base `Bib::HashParserV1` to handle IHO-specific structures:
- **editorialgroup**: IHO v1 data has nested committee arrays (`editorialgroup: [[{committee: ...}, ...]]`). Each committee is converted to a `contributor` with `role type="author"` / `description="committee"`, organization "International Hydrographic Organization"/"IHO", and nested `subdivision` elements for sub-committees.
- **commentperiod**: Moved from top-level into `ext`.
- Factory methods (`bib_item`, `create_doctype`, `create_relation`) return IHO-specific classes.

This module is required on demand (`require "relaton/iho/hash_parser_v1"`) and not auto-loaded by the main `relaton/iho` entry point.

### Load Order Constraint

In `item.rb`, `require_relative "relation"` is placed **after** the `Item` class definition because `Relation` → `ItemBase` → `Item` creates a circular dependency if loaded before `Item` exists.

### Data Retrieval

`Bibliography.search`/`.get` fetches YAML from the relaton-data-iho GitHub repo via `Relaton::Index`, then deserializes into model objects.

**Editions and series (the pubid 2.0.5 component model, relaton#440).** The pubid attribute is `edition` (dotted `a.b.c`, `IHO B-12 3.0.0`; the pre-440 name `version` is gone). A reference with no edition answers with the **latest**: `recency_key` compares the segments as integers (`2.10.0` after `2.9.0`). It used to be `min_by` on the string, which returned the oldest.

**Serial locators are volumes (relaton#440 unified the year locators of relaton#407).** The yearbook year IS a volume: `IHO P-5 Vol. 2020` is canonical, the bare-year faces (`P-5 2020`, `P-5/2020`) parse as legacy aliases into the same `volume`, and the IHR is `P-1 Vol. 30` with `Issue 1` (no parens) or the short slash form `P-1/30`. A bare series query answers with the latest volume/issue. **Components can publish separately and carry their own edition:** `IHO S-66 Suppl 1 2.0.0` gives `supplement_edition`, `S-100 Part S-102 1.0.0` gives `part_edition`, annexes likewise — and the publication years in parens (`S-52 Annex A 4.0.3 (2021)`) are `*_year` metadata, not identity: a stated year pins the record, an omitted one wildcards. Matching (`pubid_match?`) treats a discriminator the query omits as a wildcard: `IHO P-1 Vol. 30` matches any issue of volume 30. The comparison runs through pubid's `#exclude` — excluding `:volume` nils the `issue`, excluding an `:appendix` nils its `appendix_subnumber` (scalar clusters) — the way BIPM's `stem_keys` does. The subdivisions (part/appendix/annex/supplement) stay strict: this flavor cannot use the `===` subset match, because pubid does not declare `subset_strict` for IHO's subdivisions and a nil `part` would read as "any part" (`IHO S-100` would answer with a part row).

**The edition reaches the index only through the committed row.** A record prints `B-12` and keeps its edition in `edition:`, so `relaton index` cannot read a version from the docid. `MachineIndex#refine` (relaton-cli) takes the committed `index-v3.yaml` row when it adds only a key in `REFINABLE_KEYS` to the parse — `version`/`edition`/`volume`/`year`/`issue` (relaton#407 added the year/issue pair for the series rows). Before that, the Pages index (generated 2026-10-29) had no `version` in any of its 325 rows, so every versioned reference answered not-found (relaton-data-iho#20). The suite did not see it: `spec/fixtures/index-v3.zip` is the committed index, which has versions. The suite's fixture carries the #48-era re-keyed series rows migrated to the #440 keys (`version`→`edition`/`<component>_edition`, year locators→`volume`; `support/migrate_index_fixture.rb` did the one-shot migration) — refresh the fixture from the live published zip once relaton-data-iho round 2 republishes, and reconcile any file-name drift then.

### Test Infrastructure

- **VCR cassettes** (`spec/vcr_cassettes/`): recorded HTTP responses for offline testing
- **RelaxNG validation**: specs validate XML output against `grammars/relaton-iho-compile.rng` using ruby-jing
- **Fixtures** (`spec/fixtures/`): reference XML/YAML documents for round-trip serialization tests

### IHO-Specific Document Types

policy-and-procedures, best-practices, supporting-document, report, legal, directives, proposal, standard

## Testing

- **Index fixture:** `spec/fixtures/index-v1.zip` is pre-loaded into `Relaton::Index` pool in `before(:suite)` (configured in `spec/support/webmock.rb`). Run `rake spec:update_index` to refresh from relaton-data-iho.
