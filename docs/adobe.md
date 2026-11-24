# adobe — architecture notes

Dev notes for the `Relaton::Adobe` flavor. Excluded from the packaged gem via
the gemspec `files` glob (dev docs only). See the root `CLAUDE.md` for the
cross-flavor conventions.

## What Adobe is

`Relaton::Adobe` covers Adobe technical publications: **font tech notes** (the
`adobe-type-tools/font-tech-notes` repo, numbered `ATN<NNNN>` / "Adobe Technical
Note #<number>") and **named publications** cited by PDF-Association standards
(Adobe Glyph List, PostScript Language, the Adobe-Japan1/GB1/CNS1/Korea1/KR-9
character collections, etc.). Records live in the `relaton-data-adobe` data repo.

The flavor mirrors the shape of `Relaton::Iala` — a thin model layer over
`Relaton::Bib` plus a `Bibliography` retrieval front-end.

## Two doctypes

`Doctype::TYPES` (`doctype.rb`) is `%w[tech-note publication]`, carried in the
inherited `content` attribute:

- **`tech-note`** — numbered notes; `tech_note_number` + `source_repo_path` set.
- **`publication`** — slug-keyed named publications; `publication_slug` set.

## Typed Ext (`ext.rb`)

`Relaton::Adobe::Ext < Bib::Ext` adds Adobe-specific structured metadata so it
round-trips natively through **both** XML and YAML (no per-repo merge hacks):
`urn`, `webpage`, `tech_note_number`, `source_repo_path`, `publication_slug`.
Each is declared in both the `xml` and `key_value` mapping blocks. The elements
land directly under `<ext>` (alongside the inherited `doctype`/`flavor`); the
RelaxNG grammar (`grammar/relaton-adobe.rng`) extends `BibDataExtensionType`
(`combine="interleave"`) with the five optional elements and restricts
`DocumentType` to the two doctypes. `spec/adobe/relaton/adobe/xml_spec.rb`
Jing-validates the produced XML against it.

## Docidentifier (pubid-backed, mirrors OIML)

`Relaton::Adobe::Docidentifier < Bib::Docidentifier` **soft-parses** its `content`
into a `Pubid::Adobe` identifier held in `@pubid` (a `TechNote` or `Publication`),
exactly like `Relaton::Oiml::Docidentifier`:

- `content=` runs `::Pubid::Adobe.parse` and rescues — a non-canonical string
  (e.g. a title-cased `"Adobe Glyph List"`, vs the canonical
  `"Adobe Publication adobe-glyph-list"`) leaves `@pubid` nil while the plain
  `content` string still round-trips.
- The base class's abstract `remove_part!` / `remove_date!` / `to_all_parts!`
  (which otherwise raise `NotImplementedError`) are implemented as **safe no-ops**
  over the pubid: Adobe identifiers carry no part/date/all-parts component, so
  these keep `Bib::ItemData#to_most_recent_reference` / `#to_all_parts` from
  raising and never change the rendered `content`.

`require "pubid"` (in `adobe.rb`) exposes `Pubid::Adobe`. pubid is already a
gemspec dependency (shared with iso/oiml/…), so no new dep was added.

## Retrieval flow (pubid-backed, mirrors OIML)

`Processor#get` (`processor.rb`) → `Bibliography.get` → `Bibliography.search`
(`bibliography.rb`), modelled on `lib/relaton/oiml/bibliography.rb`:

1. Parse the reference with `::Pubid::Adobe.parse` (`pubid_for`); an unparseable
   ref is a **graceful miss** (logged, returns nil) rather than a raised Parslet
   error — it only reached here because it matched the flavor prefix regex.
2. Look up in the `relaton-data-adobe` `index-v2` via
   `Relaton::Index.find_or_create(:adobe, …, pubid_class: ::Pubid::Adobe::Identifier)`,
   so each row's `:id` is a `Pubid::Adobe` identifier. **Tech notes narrow by
   number** (binary search); **publications have no number**, so `search(nil)`
   scans and the block filters. `pubid_match?` compares `row_id.to_s == query.to_s`
   — the human render is a stable identity key (drops a tech note's filename
   slug so `ATN5014` matches a slug-carrying record; includes a publication's
   slug+version). Unlike OIML there is **no edition-year selection** — each
   reference maps to a single record.
3. `Net::HTTP.get_response` for the row's `:file` under `ENDPOINT`
   (`raw.githubusercontent.com/relaton/relaton-data-adobe/main/`).
4. `Relaton::Adobe::Item.from_yaml` → an `ItemData`, date-stamped via `fetched=`.

Network/HTTP errors become `Relaton::RequestError`. **Do not** delegate `get`
back into `Relaton::Db#fetch` — that both mis-arities (`Db#fetch` is 1..3 args)
and re-enters the dispatcher, so it can never resolve.

The `Processor` registers `short = :relaton_adobe`, `prefix = "Adobe"`,
`defaultprefix = /^(?:Adobe|ATN)/` so both `Adobe Technical Note #5014` and
`ATN5014` route here.

## Sources and canonical citation forms (relaton#601)

`relaton-data-adobe` combines three Adobe source trees (52 records,
2026-11-23), for the Adobe documents that PDF Association work cites
(metanorma-pdfa#114, relaton-data-adobe#9):

- `adobe-type-tools/font-tech-notes` — the font tech notes (`ATN<NNNN>`), the
  Type 1 spec (`t1-spec`), the glyph lists and the CMap collections.
- `adobe/dc-acrobat-sdk-docs` `docs/pdfstandards/` — the PDF Reference
  editions 1.0–1.7 (there is no 1.1 edition in the tree).
- `pdfa.org/norm-refs/` — the PDF Association's mirror of the 5xxx Acrobat
  tech notes (5001, 5044, 5116, 5411, 5620, 5660), plus TIFF 6.0, XFA 3.3,
  PLRM 3.0 and the signature build dictionary 1.4.

The flavor needs no code per source. A citing document writes one of two
canonical forms:

- `Adobe TN <n>` (also `Adobe Technical Note #<n>`, `ATN<n>`);
- `Adobe Publication <slug>[-<version>]` — e.g.
  `Adobe Publication pdf-reference-1.7`, `Adobe Publication tiff-6.0`. A
  versionless `Adobe Publication pdf-reference` does **not** match an edition:
  `pubid_match?` is exact identity.

A bare slug (`pdf-reference-1.7`) is not claimable: `@defaultprefix` claims
only `Adobe`/`ATN`, as every flavor claims an explicit token.

**The dotted version needs pubid#770**, which is on pubid `main` and in no
release (2.0.49 raises `Pubid::Errors::ParseError` on
`Adobe Publication pdf-reference-1.7`). The `Gemfile` rides pubid from git at
that commit. At the next pubid release, return to a rubygems pin and floor
`relaton.gemspec` there, or a released relaton answers "not found" for every
dotted-version publication.

`spec/adobe/relaton/adobe/corpus_spec.rb` is the acceptance list: each cited
document routes to this flavor and resolves to its own row in
`spec/adobe/fixtures/index-v2.yaml` (the live index, copied wholesale). The
cited documents with no record (PDF 1.1, PDF32000_2008, the Adobe Supplement to
the ISO 32000) are `pending`; when a record lands, move its entry and refresh
the fixture.

**A record's primary docidentifier is its canonical id.** Until
relaton-data-adobe#12 (2026-11-24) a publication record carried its title
there (`Adobe Publication PDF Reference: Adobe Portable Document Format,
Version 1.7`). The lookup still worked (the index is built from the record
`id`), but `Docidentifier#pubid` was nil, `Db#item_key` gave the document no
cache row of its own, and an api.relaton.org answer was always discarded (its
key did not equal the query key). `item_spec.rb` pins the canonical form on
the `pdf-reference-1.7` fixture.

## Testing

- `bundle exec rake spec:adobe` — run the Adobe suite.
- Specs live in `spec/adobe/relaton/adobe/` and run self-contained (see the root
  `CLAUDE.md` Testing section). `xml_spec.rb` covers schema validation;
  `docidentifier_spec.rb` covers pubid parsing + the mutation hooks;
  `bibliography_spec.rb` covers the offline retrieval path (tech-note narrowing,
  publication scan, ATN-alias identity, versioned editions, graceful miss);
  `item_spec.rb` and `xml_spec.rb` load two published records
  (`spec/adobe/fixtures/`); `corpus_spec.rb` is the PDF Association
  acceptance list.
