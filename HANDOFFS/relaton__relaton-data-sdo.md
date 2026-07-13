# Hand-off: create the `relaton-data-sdo` data repo

**Target project:** a new GitHub repo `relaton/relaton-data-sdo` (does not exist
yet). This is the data companion to the `Relaton::Sdo` client just added to the
`relaton` gem (`lib/relaton/sdo/`, entry point `Relaton.organization`).

## Why

metanorma#346 ("Central logo store") and relaton-db#132 ("abbreviation → org
name") need a store of SDO organization metadata: names/translations plus logos
in multiple **formats / sizes / styles**. The existing proof-of-concept
`relaton/data-sdo-metadata` (Paneron/**vCard**, stalled since Nov 2024) is
**unfit**: vCard's `LOGO` is a single URL with no format/size/style sub-typing,
and its logos are external hotlinks, not versioned PDF-ready assets. This repo
replaces it with a purpose-built manifest.

The `relaton` client already consumes a single published **`index.yaml`** from
this repo (`Relaton::Sdo::Config::DEFAULT_URL`, currently
`https://raw.githubusercontent.com/relaton/relaton-data-sdo/main/index.yaml`).
Match that path, or tell us the final URL so we can update the default.

## What to build

### 1. Repo layout (versioned assets + per-org source)

```
orgs/
  iso/
    metadata.yaml        # names + translations (see schema)
    logos.yaml           # this org's logo variants
    logos/
      default-700x300.eps
      default-700x300.png
      red-latest.svg
      logo_iso_1972.png
  iec/ …
index.yaml               # BUILT artifact (all orgs merged) — see step 3
```

Seed with the flavors @Intelligent2013 has PDF-ready assets for (from the
metanorma#346 thread / mn-native-pdf XSLTs): **ISO, IEC, IEEE, IHO, NIST, OGC,
BSI**. Use the real extracted PDF/Word logos, not website hotlinks.

### 2. Manifest schema (what the client parses)

The client (`Relaton::Sdo::Organization.from_hash` / `Logo.from_hash`) expects:

```yaml
organizations:
  ISO:                         # key = abbreviation (case-insensitive lookup)
    name:
      - content: International Organization for Standardization   # default (no language)
      - language: fr
        content: Organisation internationale de normalisation
    logo:
      - style: default         # PRIMARY discriminator for multiple logos per org
        format: eps            # file suffix
        size: 700x300          # optional; free-form "WxH"
        url: https://<published-asset-url>/iso/default-700x300.eps
      - style: red
        format: svg
        url: https://<published-asset-url>/iso/red-latest.svg
        applicability: "stage>=60; latest layout"   # OPAQUE text; client never parses it
```

Rules:
- **`style`** differentiates variants (e.g. `default`, `red`, `grey`,
  `iso_1972`, `white_paper_2022`, BIPM `si_aspect_full`). The metanorma XSLT
  comments in metanorma#346 are the source for which variants exist per org.
- **`url`** must be an absolute, stable URL to the raw asset (e.g. GitHub raw or
  the Pages deployment). The client GETs it lazily for `logo.content` /
  `.data_uri` / `.save`.
- **`applicability`** is free-form guidance (publication year, stage, doctype,
  cover-color). The client exposes it verbatim; **metanorma** does the selecting.
  Do not invent a rigid schema for it yet.

### 3. Build + publish `index.yaml` via GHA

Add a GitHub Action that, on push to `main`, merges every `orgs/*/metadata.yaml`
+ `orgs/*/logos.yaml` into the single top-level `index.yaml` under an
`organizations:` map keyed by abbreviation, rewrites each logo `url` to its final
published location, and commits/publishes it (raw on `main`, or GitHub Pages).
Keep the published `index.yaml` small — metadata only; the binaries are fetched
on demand by URL, never inlined.

## How `relaton` consumes it (for reference / testing)

```ruby
org = Relaton.organization("ISO")
org.name                                   # "International Organization for Standardization"
org.name("fr")
org.logo_query(format: "eps", style: "default")   # => [Relaton::Sdo::Logo, …]
logo = org.logo(format: "eps", style: "default")
logo.content     # binary; logo.data_uri; logo.save("iso.eps")
```

`Relaton::Sdo::Config` lets a consumer override `url`, `storage_dir`, `storage`
(swappable, e.g. S3), and `ttl` (24 h default). Once the repo publishes a real
`index.yaml`, confirm the URL matches `DEFAULT_URL` (or send the final URL to
update it in `lib/relaton/sdo/config.rb`).

## Out of scope (future)

- Structured, machine-readable `applicability` for auto-selection.
- Migrating/decommissioning `relaton/data-sdo-metadata` (superseded by this repo).
- Paneron GUI authoring (the data is plain YAML; a GUI can come later).
