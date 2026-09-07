# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RelatonBib is a Ruby gem that implements the [BibliographicItem model](https://github.com/metanorma/relaton-models#bibliography-uml-models) for bibliographic reference management. It's part of the Relaton ecosystem and serves as the base library for other Relaton gems.

## Common Commands

```bash
# Install dependencies
bundle install

# Run all tests
bundle exec rake spec

# Run a single test file
bundle exec rspec spec/relaton_bib/bibliographic_item_spec.rb

# Run a specific test by line number
bundle exec rspec spec/relaton_bib/bibliographic_item_spec.rb:42

# Run linting
bundle exec rubocop

# Auto-fix linting issues
bundle exec rubocop -a

# Interactive console
bin/console
```

## Architecture

### Serialization Layer (lutaml-model)

The codebase uses [lutaml-model](https://github.com/lutaml/lutaml-model) for serialization. Each model class in `lib/relaton/bib/model/` inherits from `Lutaml::Model::Serializable` and declares attributes with XML/YAML/JSON mappings.

### Core Classes

**`Relaton::Bib::Item`** ([lib/relaton/bib/model/item.rb](lib/relaton/bib/model/item.rb)) - The main serialization class defining all bibliographic attributes and their XML mappings. Uses `ItemData` as its underlying model.

**`Relaton::Bib::ItemData`** ([lib/relaton/bib/item_data.rb](lib/relaton/bib/item_data.rb)) - The data container class that holds bibliographic data and provides conversion methods (`to_xml`, `to_yaml`, `to_bibtex`, `to_rfcxml`). This separation allows the same data to be serialized differently (bibitem vs bibdata).

**`Relaton::Bib::Bibitem`** and **`Relaton::Bib::Bibdata`** - Variants of `Item` with different XML root elements and attributes (bibitem excludes `ext`, bibdata excludes `id`).

### Component Models

Each bibliographic attribute has its own class in `lib/relaton/bib/model/`:

- `Title`, `LocalizedString`, `LocalizedMarkedUpString` - text with language/script
- `Contributor`, `Person`, `Organization` - contributors and affiliations
- `Docidentifier` - document IDs (DOI, ISBN, etc.)
- `Date` - publication dates with custom `StringDate` type
- `Relation` - related documents (circular reference with Item)
- `Ext` - extension data (doctype, ICS codes, structured identifiers)

### Sanitizing marked-up content

**`Relaton::Bib::Sanitizer`** ([lib/relaton/bib/sanitizer.rb](lib/relaton/bib/sanitizer.rb))
strips markup outside the basicdoc set. `LocalizedMarkedUpString#content=` calls it on
assignment, so every `Title`, `Abstract`, `Note`, `Formattedref` and `Docidentifier` in
every flavor passes through it. Two properties are load-bearing:

- **It does not give up on an undeclared namespace prefix.** Third-party markup prefixes
  its elements — Crossref returns JATS as `<jats:p><jats:italic>x</jats:italic></jats:p>`,
  sometimes with an `xlink:` prefix on an attribute — and Relaton never declares the prefix.
  Nokogiri reports an undeclared prefix as a parse error, so the old
  `return content if fragment.errors.any?` returned exactly the markup that most needed
  sanitizing. The undeclared prefix then reached the bibdata XML, relaton-render's
  `sanitise_citations_input_string` returned nil, and isodoc raised
  `NoMethodError: undefined method '[]' for nil` (metanorma-pdfa#99). `parse_with_prefixes`
  now declares each prefix on a wrapper element, parses, and removes **only the wrapper's
  own** declarations, matched by identity rather than by URI — `remove_namespaces!` would
  also strip a namespace the content declares itself, such as the MathML `xmlns` inside an
  opaque `<stem>`. `wrapper_name` renames the wrapper while the content contains it, so the
  content cannot close it early — in **one** scan (`NS_WRAPPER_RX`), because growing the
  name and re-testing with `include?` is quadratic, the same trap the root `CLAUDE.md`
  records for relaton-cli's `strip_tags`. An undeclared prefix inside `<stem>` goes as well
  (`<mml:math>` → `<math>`): an undeclared prefix in the output is the failure being fixed.
  Un-prefixing an attribute renames it, so `drop_attribute_namespaces` **drops** a prefixed
  attribute whose plain name the element already carries — keeping both would emit
  `target="a" target="b"`, which Nokogiri rejects as `Attribute target redefined`, and that
  is the very unparseable output this path exists to prevent. Test the collision with
  `plain_attribute?`, not `Node#attribute`, which matches on the name alone and so finds the
  prefixed attribute itself. The guard for genuinely malformed input stays — unbalanced tags,
  a stray `<`, and text that only looks like a prefixed tag are all returned untouched.
- **It does not indent.** `SAVE_OPTS` drops Nokogiri's `FORMAT` default, so
  `sanitize("<p><em>x</em></p>")` returns the input rather than `"<p>\n  <em>x</em>\n</p>"`.
  Don't reintroduce a bare `to_xml`.

### Parsing

- **`HashParserV1`** ([lib/relaton/bib/hash_parser_v1.rb](lib/relaton/bib/hash_parser_v1.rb)) - Converts legacy Hash/YAML format to `ItemData`
- **`Converter::BibXml`** ([lib/relaton/bib/converter/bibxml.rb](lib/relaton/bib/converter/bibxml.rb)) - Parses RFC BibXML format via `Relaton::Bib::Converter::BibXml.to_item`
- **lutaml-model native** - `Item.from_xml`, `Item.from_yaml`, `Item.from_json` handle current format

### Rendering

- **`Renderer::BibtexBuilder`** - Converts `ItemData` to BibTeX format
- **`Converter::BibXml`** - Converts `ItemData` to RFC XML format via `Relaton::Bib::Converter::BibXml.to_xml`
- **lutaml-model native** - `to_xml`, `to_yaml`, `to_json` via the serialization classes

### Usage Pattern

```ruby
# Parse from YAML
item = Relaton::Bib::Item.from_yaml(yaml_string)

# Parse from XML
item = Relaton::Bib::Bibitem.from_xml(xml_string)
item = Relaton::Bib::Bibdata.from_xml(xml_string)

# Parse from RFC XML
item = Relaton::Bib::Converter::BibXml.to_item(xml_string)

# Convert to different formats (returns string)
item.to_xml                    # as <bibitem>
item.to_xml(bibdata: true)     # as <bibdata>
item.to_yaml
item.to_bibtex
item.to_rfcxml
```

## Code Style

- Follows Ribose OSS Ruby style guide (inherited via `.rubocop.yml`)
- Target Ruby version: 3.1+
- Uses YARD documentation comments
