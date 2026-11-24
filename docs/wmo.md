= WMO flavor

Relaton::Wmo cites World Meteorological Organization documents: the
WMO-No. series (technical regulations and guides), WMO/TD technical
documents, JCOMM technical reports, GAW reports, and WMO-published
S-100 product specifications.

== Identity

Identifiers are `Pubid::Wmo` (pubid#763 plus the widening round: volume
faces, compound editions, the series heads). The processor claims the
canonical heads via `@defaultprefix`:

  ^(WMO-No\.|WMO/TD-No\.|JCOMM|GAW)\s

A bare S-number ("S-411") deliberately leads NO prefix: it is the shared
S-100 lexical form of two assigning authorities (IHO and WMO), and
neither flavor owns the routing (pubid#469). A `WMO`-headed reference
("WMO S-100...") routes here by its own token.

== Dataset

relaton-data-wmo (https://github.com/relaton/relaton-data-wmo) — one
record per document, `id:` the parseable Pubid::Wmo form. Its Indexer
parses each record `id` into index-v2; the consumer reads the Pages
machine index (`INDEXFILE`, `PAGES_URL`) and matches rows by the pubid
render (`pubid_match?`), like Adobe.

== Docidentifier

`Relaton::Wmo::Docidentifier` soft-parses `content` into a Pubid::Wmo
(non-WMO strings leave `@pubid` nil and round-trip as plain content).
WMO ids carry no part/date components — edition and volume live on the
record — so the base class's abstract mutation hooks are no-ops.

== Ext

`Ext` adds `doctype` (the series vocabulary: technical-regulations,
technical-document, technical-report, report, specification), `urn`,
and `webpage`. The grammar is `grammar/relaton-wmo.rng`.
