# The CitationStyle declarative language

This document is the definition of the declarative language citation
styles are written in — the contract between the style instances (data),
the rendering engines (Ruby: `Relaton::Render::Iso690`; TypeScript:
`relaton-ts` `src/citation`), and the conformance corpus
(citation-testsuite). The engines hold **no styles, no vocabularies, no
i18n**: every rendering decision is data, and both engines evaluate the
same instances to byte-identical strings.

The language is the ISO 690 model made executable: a style instance
places the standard's data elements (clause 7) in each resource kind's
order (clause 8) through declared templates, name forms, and localized
strings.

## Instance anatomy

An instance is a YAML document loaded into the `CitationStyle` model
(`relaton-models` citation module; Ruby: `lib/relaton/render/iso690/style.rb`).

```yaml
name: "ISO 690 (JIS, ja)"     # human-readable instance name
family: iso690                # presentation family: iso690 | lncs | chicago | ieee-sa | apa
extends: author-date          # optional: named instances this one deltas over
requires: [some-engine-capability]   # engine capabilities addressed; a resolver
                                     # lacking one fails loudly, never mis-renders
scheme:      # the citation scheme (see below)
templates:   # the template map (see below)
per_type: [] # per-resource-kind template variants (see below)
sort_key: [] # reference-list sort rules
types: {}    # pack-declared taxonomy: wire type -> kind
rules: {}    # presentation-of-models selections: slot -> named engine rule
```

`extends` resolves at load with documented merge semantics
(`Style#merge_delta`): collections merge per key, scalars replace, and
cycles are rejected. A delta instance carries only what it changes over
its base.

### Scheme

```yaml
scheme:
  system: name-date           # the citation system
  shortFromReference: true    # in-text short form derives from the reference
  homeDocidType: []           # docidentifier types that make a record "home"
  defaultKind: ""             # kind for records the taxonomy cannot place
  nameForm:                   # how names are rendered (see below)
  locale:                     # style-localized strings overlaying the language pack
```

`nameForm` flags (all have engine defaults; a style declares only what
it departs from): `initials`, `initialsSeparator`, `initialsPeriod`,
`givenNameFirst`, `invertedAll`, `surnameUpcase`,
`subsequentSurnameUpcase`, `completenameUpcase`, `orgUpcase`,
`editorsMarked`, `loneEditorMarked`, `rolePlacement`, `listStyle`,
`creatorFallback`, `etalCount`/`etalDisplay` and the `inText*` et-al
forms.

### Templates

```yaml
templates:
  titleOpen: "_"        # emphasis marks around the title
  titleClose: "_"
  identifierMode: first # which docidentifier renders: first | all
  citation: "{{surname}} {{date}}"          # the in-text citation
  reference: "{{creator}}{{role}}. {{title}}. …"   # the reference-list entry
  name: "{{surname}} {{givenNames}}"        # a person name inside creator
  series: ""            # the series placeholder form
  uri: ""               # the URI form
  creators: ""          # the multi-creator join form
```

A template is a string of `{{slot}}` placeholders evaluated over the
field map the engine resolves for the record (`Fields#to_h`). Every
slot renders as a present/absent pair — an absent slot's placeholder
and its attached punctuation drop out rather than rendering empty. The
placeholder vocabulary is the ISO 690 clause 7 element inventory:
`creator`, `role`, `title`, `edition`, `medium`, `series`,
`production`, `date`, `size`, `extent`, `location`, `componentpart`,
`authorizer`, `uri`, plus the name-level `surname`, `givenNames`.

### Per-type variants

```yaml
perType:
  - type: report        # wire type (the taxonomy maps it to a kind)
    home: true          # variant applies to home-docid records
    template: "…"       # overrides templates.reference for the kind
    short: "…"          # the short (container) form
    title: "…"          # the kind's title form (carries the whole emphasis)
    series: "…"         # the kind's series form
    production: "…"
    authorizer: "…"
    noPlace: true       # suppress the place placeholder
    fallbacks:          # slot -> literal when the record lacks it
      date: "n.d"
```

Variants merge per `(type, home)` key over `extends` chains: a child's
pattern for a key replaces the base's pattern for that key and keeps
the base's other patterns.

### Localization

Two layers, style instance winning over pack:

1. **Language packs** — declarative data per language
   (`i18n/<lang>.yml`; the TS mirror is the `PACKS` table). A pack
   carries `labels` (localizable strings: `edition`, `in`, `and`,
   `dateRange`, …) and `punct` (language-varying punctuation:
   `period`, `comma`, `openParen`, `productionSep`, …).
2. **The instance's `scheme.locale`** — localized strings the style
   declares, overlaid onto the pack at load. Connective attributes
   (`and`, `in`, `availableAt`, `noDate`, `noAuthor`) map to their
   label keys; arbitrary `labels`/`punct` merge verbatim.

Templates inside labels carry one substitution: `{{ var1 }}`, populated
with a runtime number. The edition cascade is the worked example —
rendering an edition number N tries, in order: the worded label
`edition_N` ("first edition"), the `edition_ordinal` template
(`第N版`), the `edition_cardinal` template, and only then the Latin
ordinal form (`Nth ed.`). A specific label outranks a template that
would apply to any number. Worded editions are document editions
(monograph, component part, serial part, report — a standard is one);
other kinds read as `version N`.

## Resolution semantics the language assumes

These engine contracts are part of the language contract — an instance
written against them renders identically on any conforming engine:

- **One citation language.** Localizable values resolve to the
  variants declared in the render language; when none match, all
  variants are eligible. There is no default-language preference.
- **The kind taxonomy.** Every record resolves to a kind (monograph,
  component part, serial part, article, continuing, online, report,
  …) through the engine's table, preceded by the instance's `types`
  declarations; records the taxonomy cannot place take
  `scheme.defaultKind`.
- **Identifiers.** `identifierMode` selects which docidentifier
  renders; internal identifier types never surface.
- **Emphasis.** Analytic titles (component part, serial part) are not
  emphasised; the host or serial carries the emphasis. A kind's
  `title:` form, when declared, carries the whole emphasis including
  any inline markup the style wants.

## Conformance

The corpus is [citation-testsuite](https://github.com/relaton/citation-testsuite):
`records/<name>.json` (a Relaton item as loose data) and
`golden/<name>.json` (style family → expected string). Both engines
assert the golden strings verbatim; a rendering changes only with a
deliberate change to an engine or instance, reviewed, with the golden
commit alongside — **a golden never changes silently**. A style family
is added to the corpus only when both engines can render it.

The JIS families (`jis-en`, `jis-ja`) demonstrate the contract's full
reach: one record, six families, byte-identical across Ruby and
TypeScript — including the CJK punctuation, the 第N版 edition forms,
and per-language title selection.

## Distribution law (SSOT)

Style instances are declared once and consumed by every engine. The
canonical pack set lives with the schema layer (relaton-models
`citation/`); engines resolve instances through it and **must not
vendor copies** — a vendored instance is a layer declaring what the
schema layer declares, and it will drift. (relaton-ts currently vendors
`src/citation/styles/*.yml` into a generated bundle; replacing that
with consumption of the canonical pack is the tracked follow-up,
together with the LML expression of this language under
lutaml-model#1033 — the style language is the cross-language
declaration export's pilot domain.)

## Versioning

Open leg: instances do not yet declare a language version. Until the
`language_version` attribute exists, the git history of this document
is the version record, and `requires` is the only machine-readable
compatibility statement an instance can make. Adding the attribute —
and an engine rejection path for instances written against an unknown
version — is tracked work; do not introduce breaking template or
scheme changes before it lands.
