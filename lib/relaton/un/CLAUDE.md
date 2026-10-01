# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-un is a Ruby gem that provides bibliographic data models for UN documents, part of the Relaton family of gems. It extends `relaton-bib` with UN-specific metadata using the LutaML-Model serialization framework. Currently on the `lutaml-integration` branch undergoing a major migration from the old `RelatonUn` namespace to `Relaton::Un`.

## Commands

```bash
# Install dependencies
bundle install

# Run all tests (also the default rake task)
bundle exec rake spec

# Run a specific test file
bundle exec rspec spec/relaton/un/bibitem_spec.rb

# Run a specific test by line number
bundle exec rspec spec/relaton/un/bibitem_spec.rb:7

# Lint
bundle exec rubocop

# Interactive console with gem loaded
bin/console
```

## Architecture

### Flavor Model Pattern

The gem follows the Relaton flavor pattern: base classes from `relaton-bib` (`Bib::Item`) are extended with a flavor-specific `Ext` class containing UN-specific metadata.

```
Bib::ItemData (from relaton-bib)
  └── Relaton::Un::ItemData    # UN flavor identity, enables NamespaceHelper#namespace → Relaton::Un

Bib::Item (from relaton-bib)
  └── Relaton::Un::Item        # model ItemData; adds Ext attribute
        ├── Relaton::Un::Bibitem   # includes Bib::BibitemShared (for <bibitem> XML)
        └── Relaton::Un::Bibdata   # includes Bib::BibdataShared (for <bibdata> XML)
```

### Lookup

`Bibliography.get` takes a String (`UN TRADE/CEFACT/2004/32`, the `UN ` token
optional) or a parsed `Pubid::Un::Identifier`, which renders the document
symbol without the token (`TRADE/CEFACT/2004/32`) — the form the UN data
itself writes. Either becomes the symbol the search matches (`document_symbol`).
`Relaton::Db` routes UN by the `UN ` prefix (`Registry#route` falls back to
`class_by_ref`): `Pubid::Un` renders the symbol without the token, so a
`UN …` reference is not an exact parse. A symbol without the token
(`TRADE/CEFACT/2004/32`) is not routed at all — no flavor claims it — and
raises `Relaton::UnknownReferenceError`. `Pubid::Un` also parses a bare DOI
exactly (`10.6028/NIST.IR.8245`), but UN does not claim it (`10.` is a DOI
prefix), so it does not route to UN either.

### Key Classes (all in `lib/relaton/un/`)

- **ItemData** — extends `Bib::ItemData`; the UN-specific data container used by `Item` via `model ItemData`
- **Item** — extends `Bib::Item`, adds `ext` attribute of type `Ext`
- **Bibitem / Bibdata** — extend Item with shared mixins for two XML serialization formats
- **Ext** — UN-specific metadata: `doctype`, `distribution`, `session`, `submissionlanguage`, `job_number`; extends `Bib::Ext`
- **Session** — session metadata (number, date, item numbers/names, collaborator, agenda_id)
- **Doctype** — restricts document types to: recommendation, plenary, addendum, communication, corrigendum, reissue, agenda, budgetary, sec-gen-notes, expert-report, resolution

### LutaML-Model Serialization

All model classes use `Lutaml::Model::Serializable`. XML mappings are defined in `xml do` blocks:
- `map_attribute` for XML attributes (e.g., `schema-version` → `schema_version`)
- `map_element` for XML elements (e.g., `session-date` → `session_date`)
- `collection: true` for array attributes
- `values: [...]` for restricted string values

### Schema Validation

RelaxNG grammars in `grammars/` validate XML output. The compiled schema is `grammars/relaton-un-compile.rng`. Tests use `ruby-jing` for validation.

### Testing Approach

Tests are round-trip serialization tests: load a fixture, serialize to XML/YAML, compare against the original fixture. Bibitem and Bibdata specs also validate XML against the RelaxNG schema. Fixtures live in `spec/fixtures/`.

## Dependencies

- **relaton-bib** (~> 2.0.0-alpha.1) — base bibliographic model with LutaML-Model integration
- **faraday** — HTTP client
- **ruby-jing** (dev) — RelaxNG schema validation in tests
- **equivalent-xml** (dev) — XML comparison in tests
