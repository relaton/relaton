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

## Docidentifier

`Relaton::Adobe::Docidentifier < Bib::Docidentifier` is a plain subclass — the
docid string (e.g. `"Adobe Technical Note #5014"`, `"Adobe Glyph List"`) is the
canonical form. A future `Pubid::Adobe` can hook in via `#pubid` without changing
the public interface (cf. `lib/relaton/iala/docidentifier.rb`). No pubid gemspec
dep is needed today.

## Retrieval flow

`Processor#get` (`processor.rb`) → `Bibliography.get` → `Bibliography.search`
(`bibliography.rb`), mirroring `lib/relaton/iala/bibliography.rb`:

1. `index.search(text)` over the `relaton-data-adobe` `index-v2` (fetched/cached
   via `Relaton::Index.find_or_create(:adobe, …)`), taking the max `:id` row.
2. `Net::HTTP.get_response` for the row's `:file` under `ENDPOINT`
   (`raw.githubusercontent.com/relaton/relaton-data-adobe/main/`).
3. `Relaton::Adobe::Item.from_yaml` → an `ItemData`, date-stamped via `fetched=`.

Network/HTTP errors become `Relaton::RequestError`. **Do not** delegate `get`
back into `Relaton::Db#fetch` — that both mis-arities (`Db#fetch` is 1..3 args)
and re-enters the dispatcher, so it can never resolve.

The `Processor` registers `short = :relaton_adobe`, `prefix = "Adobe"`,
`defaultprefix = /^(?:Adobe|ATN)/` so both `Adobe Technical Note #5014` and
`ATN5014` route here.

## Status / follow-ups

- `relaton-data-adobe` (dataset) and `Pubid::Adobe` (identifier flavor) are
  companion work not yet published; retrieval is wired and unit-tested offline
  (webmock), but a live end-to-end fetch waits on the data repo.

## Testing

- `bundle exec rake spec:adobe` — run the Adobe suite.
- Specs live in `spec/adobe/relaton/adobe/` and run self-contained (see the root
  `CLAUDE.md` Testing section). `xml_spec.rb` covers schema validation;
  `bibliography_spec.rb` covers the offline retrieval path.
