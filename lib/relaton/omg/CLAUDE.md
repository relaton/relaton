# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

relaton-omg is a Ruby gem that searches and fetches standards from The Object Management Group (OMG) at https://www.omg.org. It is part of the larger Relaton family of bibliographic data gems (v2.0.0-alpha.1).

## Commands

- **Run all tests:** `bundle exec rspec`
- **Run a single test:** `bundle exec rspec spec/relaton/omg/item_spec.rb`
- **Lint:** `bundle exec rubocop` (follows Ribose OSS style guide)
- **Lint with autofix:** `bundle exec rubocop -a`
- **Install deps:** `bundle install`

## Architecture

### Module structure

All source lives under `lib/relaton/omg/`. The main entry point is `lib/relaton/omg.rb` which loads everything under the `Relaton::Omg` module namespace.

### Class hierarchy

The gem extends `relaton-bib` (~> 2.0.0-alpha.1), the core Relaton bibliographic data library:

- `Relaton::Omg::Item` < `Bib::Item` — base item class, uses `Omg::ItemData` model (subclass of `Bib::ItemData`)
- `Relaton::Omg::Ext` < `Bib::Ext` — overrides `get_schema_version` to return the OMG model version
- `Relaton::Omg::Bibitem` < `Item` — includes `Bib::BibitemShared`, for `<bibitem>` XML
- `Relaton::Omg::Bibdata` < `Item` — includes `Bib::BibdataShared`, for `<bibdata>` XML
- `Relaton::Omg::Docidentifier` < `Bib::Docidentifier` — the document id, backed by `Pubid::Omg`; `Item` declares it, so XML and YAML deserialization produce it too
- `Relaton::Omg::Processor` < `Core::Processor` — relaton-core integration, delegates to `Bibliography`, `Bibitem`, `Item`
- `Relaton::Omg::Bibliography` — fetches standards via `Scraper`
- `Relaton::Omg::Scraper` — scrapes https://www.omg.org/spec for bibliographic data

### References are parsed with pubid

OMG uses `Pubid::Omg` and no hand regex. OMG publishes no index and has no data
repository, so this is the BSI and CEN shape: parse the reference, and back the
document id with pubid. There is no `INDEXFILE` and no `pubid_class:`. Do not
add an index.

The grammar is `OMG <ACRONYM>[ <VERSION>][<sep><PART>]`, where `<sep>` is a
space, or a slash after a version. The version can carry a beta label (`2.5 beta`,
`2.0 beta 1`). The part is a volume or a format name (`Superstructure`, `PDF`).

- **An unrecognized reference raises.** `Scraper.scrape_page` lets
  `Pubid::Errors::ParseError` propagate, so
  `OMG Model Driven Architecture Guide rev. 2.0` raises and does not show as
  "Not found". Only the transport errors are rescued, by name.
- **The request URL is the acronym and the version, and nothing else.**
  `get_doc` builds `https://www.omg.org/spec/<ACRONYM>/<VERSION>`, with each
  space of the version turned into `/` (`1.0 beta 2` becomes `1.0/beta/2`). The
  part stays out of the URL: `fetch_link` uses it to find the part's PDF link
  on the version page, and `fetch_title` appends it. The cassettes replay only
  while the URL does not change.
- **The docid version comes from the page, not from the query.** That is why
  `get "OMG AMI4CCM"` answers `OMG AMI4CCM 1.1`. `fetch_docid` and the History
  ids of `fetch_relation` are rendered by
  `Pubid::Omg::Identifiers::Specification`, not by parsing a joined string.
- **pubid renders one separator.** `OMG DDS 1.4/PDF` renders back as
  `OMG DDS 1.4 PDF`. Both spellings name the same document, and one rendering
  keeps `==` and `matches?` true between them. If you echo a caller's
  reference, echo the string, not `pubid.to_s`.
- **Known limit.** OMG's URL spelling `Beta2` (label and number joined) parses
  as a part, not a version. It round-trips, so nothing is lost.
- **The acronym is the URL segment, verbatim.** 30 of the 270 acronyms in the
  OMG catalog carry a hyphen, a slash, a plus, or start in lower case
  (`DDS-XTypes`, `EDMC-FIBO/BE`, `VSIPL++`, `smartant`). pubid PR #376 accepts
  all 270. A slash **before** the version belongs to the acronym
  (`OMG EDMC-FIBO/BE 1.1` fetches `spec/EDMC-FIBO/BE/1.1`); a slash **after**
  the version separates the part. So `OMG UML/Superstructure` is the acronym
  `UML/Superstructure`; write the part behind a space. With pubid `ce2f75ef`
  (PR #372) those 30 raised, and the migration waited for #376. Fix a grammar
  gap in pubid; do not split the acronym in the flavor.

`Docidentifier` parses its `content` on the data side and rescues the parse, so
a value that is not an OMG identifier stays verbatim with a nil `pubid`. Its
mutators:

- `remove_date!` drops the **version**. OMG identifiers carry no date, and the
  version is the discriminator, as IALA maps `remove_date!` onto its edition.
  So `to_most_recent_reference` turns `OMG AMI4CCM 1.0` into `OMG AMI4CCM`.
- `remove_part!` drops the part: `OMG UML 2.1.1 Superstructure` becomes
  `OMG UML 2.1.1`.
- `to_all_parts!` is the inherited no-op. An OMG part is a name, not a numbered
  part, so there is no "all parts" form.

The processor sets `@pubid_flavor = :Omg`. That changes nothing today:
`Pubid::Omg.prefixes` is `["OMG"]`, the same as `@prefix`.

### Publication date comes from JSON-LD, not the visible text

`Scraper#pub_date` reads the `publicationDate` value out of the page's
`application/ld+json` block, not the `<dt>Publication Date:</dt>` text. Two
reasons, both verified against cassettes:

- **Locale.** The OMG server renders the month name in its own locale, and
  Cloudflare caches that variant. A response can carry `Content-Language: zh-CN`
  with an otherwise English page (`<html lang="en">`) and a `<dd>七月 2007</dd>`,
  which made `Date.parse` raise `Date::Error`. The request already sends
  `Accept-Language: en-us,en;q=0.5`; the CDN answers `Vary: accept-encoding`
  only, so it does not vary on language and no request header can prevent this.
- **Precision.** The visible text is a lossy render of the same value:
  `2013-03-31` prints as "March 2013". Parsing the text rounded every OMG date
  down to day 01.

The `<dd>` text stays as a fallback for a page with no JSON-LD, and a month name
it cannot parse logs a warning instead of raising.
`spec/omg/relaton/omg/scraper_spec.rb` guards all three paths with
`spec/omg/fixtures/localized_date.html`. Do not "simplify" the parser back to
the `<dd>` text.

### Serialization formats

Items can be serialized to/from YAML and XML. Tests verify round-trip fidelity for all three classes. XML output is validated against RELAX NG schemas in `grammars/`.

### Test patterns

- RSpec with `expect` syntax (monkey patching disabled)
- `equivalent-xml` for XML comparison
- `ruby-jing` for RELAX NG schema validation against `grammars/relaton-omg-compile.rng`
- VCR cassettes in `spec/vcr_cassettes/` for HTTP interaction recording
- Fixtures in `spec/fixtures/` (YAML and XML reference files)
- Tests follow a round-trip pattern: load fixture → parse → serialize → compare to fixture

## Style

- Ruby >= 3.1.0
- Rubocop inherits from Ribose OSS guide with `rubocop-rails` required but Rails cops disabled
- OMG document reference format: `OMG {ACRONYM}[ {VERSION}][ {PART}]` (e.g., `OMG AMI4CCM 1.0`, `OMG UML 2.1.1 Superstructure`)
