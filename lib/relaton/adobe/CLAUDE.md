# CLAUDE.md

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

## Status / follow-ups

- `Pubid::Adobe` (identifier flavor: `TechNote` + `Publication`, prefixes
  `["Adobe", "ATN"]`) is on pubid `main`, the version this repo pins, and is now
  wired into both `Docidentifier` and `Bibliography`.
- `relaton-data-adobe` (dataset) is not yet published; retrieval is wired and
  unit-tested offline (webmock + a stubbed pubid-class index), but a live
  end-to-end fetch waits on the data repo. When it lands, confirm rows serialize
  as `_type: pubid:adobe:{tech-note,publication}` (the `ADOBE_TYPE_MAP` pubid
  deserializes via `pubid_class`).

## Testing

- `bundle exec rake spec:adobe` — run the Adobe suite.
- Specs live in `spec/adobe/relaton/adobe/` and run self-contained (see the root
  `CLAUDE.md` Testing section). `xml_spec.rb` covers schema validation;
  `docidentifier_spec.rb` covers pubid parsing + the mutation hooks;
  `bibliography_spec.rb` covers the offline retrieval path (tech-note narrowing,
  publication scan, ATN-alias identity, graceful miss).
