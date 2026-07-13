# CLAUDE.md

Dev notes for `Relaton::Sdo` — the SDO organization & logo store.

## What this is

A **non-flavor** component that answers metanorma#346 (central logo store) and
its sister relaton-db#132 (map abbreviation → organisation name/translation).
It is **not** a bibliographic flavor: it has **no processor**, **no
`Db::Registry` entry**, and is not reachable from `Db#fetch`. It is a standalone
top-level store, exposed through `Relaton.organization`.

This deliberately honors the scope decision in `lib/relaton/db/CLAUDE.md`
("org metadata … kept out of the processors"): nothing here touches a processor.
The user's choice was to still surface it from the `relaton` gem itself (one
`require`, one entry point) as a **lazily-autoloaded** component — referencing
`Relaton::Sdo` or calling `Relaton.organization` is what loads it.

## Public API

```ruby
org = Relaton.organization("ISO")   # case-insensitive; nil if unknown
org.name                            # default (untranslated) name
org.name("fr")                      # translation, or nil
org.name(language: "fr")            # same, via the language: keyword
org.logo_query(format:, size:, style:)  # all args optional → matching Logo list
org.logo(format:, size:, style:)        # one Logo: nil if 0, the match if 1,
                                        # raises Sdo::Error if the filter is ambiguous
logo.content    # raw binary (lazy HTTP GET of logo.url, memoized)
logo.data_uri   # "data:<mime>;base64,…"
logo.save               # write to a filename derived from the URL; returns path
logo.save("/path.eps")  # write to a custom path
```

## Data model & retrieval flow

`Store` (singleton) lazily builds an index from a single **`index.yaml`**
manifest served by the `relaton-data-sdo` data repo, and memoizes it (`reset!`
drops the memo — used by specs). Shape:

```yaml
organizations:
  ISO:
    name:
      - content: International Organization for Standardization   # default
      - { language: fr, content: Organisation internationale de normalisation }
    logo:
      - { style: default, format: eps, size: 700x300, url: "https://…/iso.eps" }
      - { style: red, format: svg, url: "https://…/red.svg",
          applicability: "stage>=60" }   # opaque text; the store never interprets it
```

- **`style`** is the primary discriminator for multiple logos per org (e.g.
  `default`, `red`, `grey`, `iso_1972`, `white_paper_2022`, BIPM `si_aspect_full`).
- **`applicability`** (year/stage/doctype/cover-color rules) is carried through
  verbatim and exposed; **selection is the consumer's job** (metanorma), not the
  store's.

`Config` (`Relaton::Sdo.configuration`) holds the index `url`, the cache
`storage_dir` (default `~/.relaton/sdo`), the `storage` backend (defaults to
`Relaton::Index::FileStorage`; swappable, e.g. S3), and the `ttl` (24 h).
`Fetcher.fetch_index` serves a fresh on-disk copy within the TTL, re-downloads
otherwise, and falls back to a stale cache if the network fails. A URL with no
scheme (or `file://`) is read straight off disk — handy for fixtures/specs. Logo
binaries are fetched on demand and memoized on the `Logo` (no disk cache yet).

## Tests

`spec/sdo/` is a self-contained suite (auto-discovered by `rake spec`). It uses
WebMock to stub the index and logo URLs, points `storage_dir` at a fresh
`Dir.mktmpdir` per example, and resets the store between examples. It
`require "relaton"` because the public entry point (`Relaton.organization`)
lives in the root entry file, which the shared spec_helper does not load.

## Scope / not yet done

- The real `relaton-data-sdo` data repo (assets + build GHA) — see
  `HANDOFFS/relaton__relaton-data-sdo.md`. Until it publishes, `Config#url`
  points at its (future) raw `index.yaml`.
- No structured interpretation of `applicability`; no on-disk cache of logo
  binaries; no writeback/authoring.
