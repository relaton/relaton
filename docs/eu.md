# EU flavor (relaton#44)

`Relaton::Eu` fetches EU legal acts: regulations, directives and decisions,
cited as `EU Regulation 1227/2011`. The identifier is `Pubid::Eu` (pubid
2.0.44, pubid#752; ELI subtypes from 2.0.46, pubid#755). The data repo is `relaton-data-eu`. Its first full
crawl (2026-11-20) wrote 184,513 index rows. Its Pages index
(`index/manifest.json`) is published only when `Relaton::Eu` is on relaton
`main` and relaton/support has the Pages config, so until then a lookup raises
`Relaton::Index::Error` and the specs use fixtures only.

## Development

- `bundle exec rake spec:eu` — this flavor's suite.
- No VCR: the specs stub HTTP with WebMock. `spec/eu/fixtures/cellar/<year>.json`
  are real CELLAR answers of `Cellar::QUERY` for that year, narrowed with a
  `VALUES` clause to eleven works (the cases below). `fixtures/index-v2.yaml`
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
`dec_impl`, `dir_del`, `reg_financ`). Implementing and delegated acts
share the numbering of their type. `Pubid::Eu` reads the subtype, so the
ELI goes to pubid unchanged: `#subtype` is `"impl"`, `#to_eli` gives the
ELI back, and the subtype is in the index row but not in `==` or the
printed id (`EU Regulation 2016/1356`). A subtype pubid does not know is a
crawl error in the GitHub report. A work with no ELI (about 1,400, nearly all decisions), a
corrigendum ELI (`…/corrigendum/<date>/oj`), or another ELI type (`C`,
`convention`, …) is skipped.

**The print order comes from the title.** From 2015 every act prints
`<year>/<number>`. Before 2015 a regulation prints `No <number>/<year>`, and
a decision or a directive can print either order (`Decision No 1082/2013/EU`,
`Decision 2010/87/EU`). `Parser#keep_title_order` reads the first citation of
the act's own type in its English title (or, for an act with no English
version, its French title: `Règlement (CEE) n 2015/68`) whose pair names this
act (a two-digit year included: `Directive 93/42/EEC`) and sets
`number_first` when that order differs from pubid's default. `number_first`
is in the index row, and pubid ignores it for equality. pubid prints `No`
where the pair also reads as a later act's `<year>/<number>`: regulation 2015
of 1968 is `EU Regulation No 2015/1968`, and `EU Regulation 2015/1968` is
regulation 1968 of 2015.

## Where the data comes from

The Publications Office CELLAR SPARQL endpoint,
`https://publications.europa.eu/webapi/rdf/sparql` (Virtuoso, no key).
`Cellar` asks for one year at a time, 1,000 works a page ordered by CELEX,
one request a second (`Core::Pacer`). A 429, a 5xx or a transport error is
retried four times, after 15, 30, 60 and 120 s, then
`Relaton::RequestError`. CELLAR can answer 502/504 for a minute or more: the
first update run (2026-11-20) failed with the earlier 2–8 s waits.

A full crawl is 75 years and 247 pages for about 213,400 works (2026-11).
A 1,000-row page takes from 4 s to more than 100 s, depending on CELLAR's
load and cache (8–11 s for 2016, 34–57 s for 1988 with a cold cache,
measured with the English title only). The titles in every language make a
page about two times slower, so a full crawl takes from about 1.5 hours to
more than 4 hours. Four pages in
parallel were not faster than four in sequence: CELLAR seems to queue
heavy queries, so the crawler stays sequential.

### Full crawl and update runs

| Source | Reads | Index | Prune |
|---|---|---|---|
| `eu-cellar` | every year, 1952 to now | starts empty | yes (`prune: true`) |
| `eu-cellar-updates` | works changed since the last run | the existing one | refused (`ArgumentError`) |

An update run selects works by `cmr:lastModificationDate`
(`<http://publications.europa.eu/ontology/cdm/cmr#lastModificationDate>`)
from one day (`DataFetcher::OVERLAP`) before the start of the last
finished run, which both sources write to `cellar-since.txt` in the working
directory (the data repo must commit it). With no such file an update run
raises. A filter on that time is fast: the last 7 days were 116–212 works
in one page (2.5 s), the last 30 days 11,807 works (12 pages: CELLAR
sometimes changes many works at once).

An update run cannot see a work CELLAR deleted or one whose ELI changed
(the old file stays), nor a change outside the work (an author body's new
English label). So the full crawl still runs from time to time, for example
monthly, with the update run between, for example daily or weekly. Both
check the rows they read against a `COUNT` of the same scope.

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
| `cdm:expression_title` of each language expression (`cdm:expression_uses_language`) | one `title` type `main` per language, English, French, German first, then by CELLAR code; no-break spaces made plain, the EEA relevance note dropped; `language` and `script` list the titles' languages and scripts |

**Titles in every language.** `Cellar::QUERY` joins `<code>|<title>` per
language with `Cellar::TITLE_SEP` (`~|~`). That separator must be ASCII:
Virtuoso turns a non-ASCII character of the query text into `?`, while the
titles it returns stay UTF-8. `Parser::LANGUAGES` maps CELLAR's codes (`ENG`,
`BUL`, …) to ISO 639-1 and a script (`Cyrl` for Bulgarian, `Grek` for Greek,
`Latn` for the rest). A recent act has 23 or 24 titles (Irish is rare); an
act before 1973 has the original languages only (German, French, Italian,
Dutch), so its first title is French, as on EUR-Lex. About 15,400 crawled
acts have no English title (2026-11). All titles make a page answer about 7
times larger and about two times slower (2016: 3.2 s to 7.6 s), and add up to
about 6 KB to a document.

**The EEA relevance note** (`Parser::EEA_TEXTS`) is dropped in each language,
in the current form and in the older forms seen five times or more in a
ten-year sample (1994-2024). Rare typing errors, and the longer note that
also names the EU-Switzerland agreement, stay in the title: in five sampled
years, 75 notes stayed, none more than twice.

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
  reference's year finds nothing. `===` ignores the print order, and
  before 2015 two decisions can share a number and a year (Council Decision
  No 252/2013/EU and Commission Implementing Decision 2013/252/EU: 5 such
  pairs in the 2026-11 index). So when the search gives more than one row,
  the row whose `number_first?` equals the query's wins.

## Pending work elsewhere

- `relaton/support` — Cimas config and the Pages config (`data-index/configs.yml`
  row `eu`) for `relaton-data-eu`. The repository exists (2026-11-20); its
  Deploy publishes the Pages index only after this PR merges into `main`.
- `pubid` — joint families (`(EU, Euratom)`), two-digit years and author
  words in a title are not parsed (pubid's "Known gaps"); the parser reads
  only the number pair of a title. `Pubid::Eu#to_celex` is right only when
  CELLAR numbered the work with the act number, so relaton does not use it.
