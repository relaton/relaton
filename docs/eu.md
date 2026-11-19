# EU flavor (relaton#44)

`Relaton::Eu` fetches EU legal acts: regulations, directives and decisions,
cited as `EU Regulation 1227/2011`. The identifier is `Pubid::Eu` (pubid
2.0.44, pubid#752). The data repo is `relaton-data-eu`; it does not exist
yet, so the consumer is tested only against fixtures.

## Development

- `bundle exec rake spec:eu` — this flavor's suite.
- No VCR: the specs stub HTTP with WebMock. `spec/eu/fixtures/cellar/<year>.json`
  are real CELLAR answers of `Cellar::QUERY` for that year, narrowed with a
  `VALUES` clause to nine works (the cases below). `fixtures/index-v2.yaml`
  and `fixtures/data/` are the **output of `DataFetcher` over those
  answers**: regenerate both together by running the crawler over the page
  fixtures, never by hand.

## Scope

CELEX sector 3 (legislation), types `R` (regulation), `L` (directive) and
`D` (decision): about 161,800, 8,100 and 43,500 works (2026-11). Out of
scope: consolidated versions (`…/eli/reg/2011/1227/2024-11-08`),
corrigenda, and the other CELEX sectors.

## Identifier forms

| docidentifier type | value | primary |
|---|---|---|
| `EU` | `EU Regulation 1227/2011` | yes |
| `CELEX` | `CELEX 32011R1227` | |
| `ELI` | `http://data.europa.eu/eli/reg/2011/1227/oj` | |

`Db` accepts only the `EU …` form. A CELEX number or an ELI is not a query.

**The act identifier comes from the ELI, never from the CELEX number.** A
CELEX number is CELLAR's own sequence, and for many decisions it is not the
act number: ECB decision `2016/245` is CELEX `32016D0002`. So
`Pubid::Eu#to_celex` is not used, and the `CELEX` docidentifier is the
work's own. The ELI type can carry a subtype (`reg_impl`, `reg_del`,
`dec_impl`, `dir_del`, …). Implementing and delegated acts share the
numbering of their type, and `Pubid::Eu` reads only `reg`/`dir`/`dec`, so
`Parser::ELI` drops the subtype for the parse and the `ELI` docidentifier
keeps it. A work with no ELI (about 1,400, nearly all decisions), a
corrigendum ELI (`…/corrigendum/<date>/oj`), or another ELI type (`C`,
`convention`, …) is skipped.

**The print order comes from the title.** From 2015 every act prints
`<year>/<number>`. Before 2015 a regulation prints `No <number>/<year>`, and
a decision or a directive can print either order (`Decision No 1082/2013/EU`,
`Decision 2010/87/EU`). `Parser#keep_title_order` reads the first citation of
the act's own type in its English title whose pair names this act (a
two-digit year included: `Directive 93/42/EEC`) and sets `number_first` when
that order differs from pubid's default. `number_first` is in the index row,
and pubid ignores it for equality.

## Where the data comes from

The Publications Office CELLAR SPARQL endpoint,
`https://publications.europa.eu/webapi/rdf/sparql` (Virtuoso, no key).
`Cellar` asks for one year at a time, 1,000 works a page ordered by CELEX,
one request a second (`Core::Pacer`). A 429, a 5xx or a transport error is
retried five times, then `Relaton::RequestError`. A 1,000-row page answers in
about two seconds; a full crawl is about 215 pages.

**Write a property name with a hyphen as a full IRI.** Virtuoso misreads
`cdm:resource_legal_date_entry-into-force` as a prefixed name: it answers,
with values from no such property (`2016-04-15` for acts that entered into
force months later). `Cellar::QUERY` uses
`<http://publications.europa.eu/ontology/cdm#resource_legal_date_entry-into-force>`
and the same form for `resource_legal_in-force`.

| CDM property | ItemData |
|---|---|
| `cdm:resource_legal_id_celex` | docidentifier `CELEX`; `source` (EUR-Lex page) |
| `cdm:resource_legal_eli` | the act identifier; docidentifier `ELI` |
| `cdm:work_date_document` | `date` type `issued` |
| `…#resource_legal_date_entry-into-force` | `date` type `implemented`: the first one, without CELLAR's `1001-01-01` placeholder |
| `…#resource_legal_in-force` | `status` stage `in-force` / `not-in-force` |
| `cdm:work_created_by_agent` + its `skos:prefLabel` (en) | contributors, role `author`, abbreviation the corporate-body code (`EP`, `CONSIL`, `COM`, `ECB`); the Publications Office (`OP`) is the publisher |
| `cdm:resource_legal_repeals_resource_legal` | relation `obsoletes`, the target by CELEX |
| `cdm:resource_legal_amends_resource_legal` | relation `updates`, the target by CELEX |
| `cdm:expression_title` of the English expression | `title` (no-break spaces made plain, the `Text with EEA relevance` note dropped) |

A relation names its target by CELEX, because the row has no act identifier
for it. The item is a plain `Bib::ItemData` with `type: standard` and `ext`
doctype `regulation`/`directive`/`decision`, flavor `eu`. There is no EU
grammar: the specs validate against `grammar/biblio-compile.rng`. A data file
carries no `fetched`; `Bibliography#fetch_doc` sets it on reading.

## Shape

The SAE shape (`docs/sae.md`):

- **Producer** — `DataFetcher` (`relaton fetch-data eu-cellar`) reads every
  year from 1952 to this year and writes one file per act, named after the
  act identifier (`data/eu-regulation-1227-2011.yaml`). Two works with one
  act identifier keep the first, with a warning. A page that keeps failing
  raises before `index.save`, so a `prune: true` run publishes nothing.
- **Index** — `INDEXFILE = "index-v2"`, rows keyed by
  `pubid_class: ::Pubid::Eu::Identifier`, read through `PAGES_URL`.
- **Consumer** — `Bibliography.get` does `index.search(pubid)` (`===`: the
  type and the year are compared, the legal family is a wildcard) and reads
  the document from `ENDPOINT`. A year argument that differs from the
  reference's year finds nothing.

## Pending work elsewhere

- `relaton/support` — Cimas config for `relaton-data-eu`; the repository
  itself is created by its owner.
- `pubid` — the ELI subtypes, joint families (`(EU, Euratom)`), two-digit
  years and author words in a title are not parsed (see the hand-off).
