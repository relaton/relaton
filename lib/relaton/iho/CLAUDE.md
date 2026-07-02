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

### Test Infrastructure

- **VCR cassettes** (`spec/vcr_cassettes/`): recorded HTTP responses for offline testing
- **RelaxNG validation**: specs validate XML output against `grammars/relaton-iho-compile.rng` using ruby-jing
- **Fixtures** (`spec/fixtures/`): reference XML/YAML documents for round-trip serialization tests

### IHO-Specific Document Types

policy-and-procedures, best-practices, supporting-document, report, legal, directives, proposal, standard

## Testing

- **Index fixture:** `spec/fixtures/index-v1.zip` is pre-loaded into `Relaton::Index` pool in `before(:suite)` (configured in `spec/support/webmock.rb`). Run `rake spec:update_index` to refresh from relaton-data-iho.
