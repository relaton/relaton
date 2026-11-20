# arxiv — architecture notes

The arXiv flavor (relaton#42) fetches arXiv e-prints live from the arXiv API.
It has no data repo and no index.

## Flow

`Processor#get` → `Bibliography.get(ref)` → `Api.feed(id)`
(`GET https://export.arxiv.org/api/query?id_list=<id>`, Atom) →
`Parser.parse(xml)` → `Bib::ItemData`.

- **Identifiers are `Pubid::Arxiv`** (pubid 2.0.44, pubid#753; the gemspec
  floors pubid there). The processor sets `@pubid_flavor = :Arxiv`, so the
  prefixes and the `Db` cache key come from pubid. `Pubid.parse` routes by a
  case-sensitive prefix, so `Registry#route` reaches arXiv by the exact parse
  only for `arXiv:…`; the prefix regex (`/^arXiv[:\s]/i`) routes `arxiv:…`,
  and `Processor#cache_pubid` parses it with `Pubid::Arxiv.parse`, which reads
  any case and a bare id.
- **The year option is not folded into the key** (`Processor#fold_year`
  answers the pubid as it is): the id carries its year and month, and pubid
  holds them as identity. Side effect: `Db` reads a row fetched with a year
  as dated, and does not expire it, so `fetch("arXiv:1706.03762", "2017")`
  keeps the version it cached first. Pass no year to follow new versions.
- **Versions.** `Bibliography.get` asks for `to_s(with_publisher: false)`.
  An unversioned id answers arXiv's latest version; the item's primary
  docidentifier is always the versioned id, so the query row and the
  document row of the `Db` cache are different keys for one file.
- **Errors.** A feed with no `<entry>` is how arXiv answers an id it does not
  have: nil. A non-200 answer or a network error raises
  `Relaton::RequestError` (`Db#net_retry` retries it). A reference
  `Pubid::Arxiv` cannot read is a miss with a log line.

## Mapping

See `lib/relaton/arxiv/README.adoc`. The second docidentifier is arXiv's
DataCite DOI, `10.48550/arXiv.<id without version>`, which exists for old
and new ids. `Relaton::Doi` answers the same paper by that DOI, from
DataCite. A relation item is a `Bib::ItemData`, not an `ItemBase`: the YAML
serializer rejects an `ItemBase` there (`Lutaml::Model::IncorrectModelError`).

There is no `grammar/arxiv*.rng`: the item is a plain `Bib::ItemData`
(flavor `arxiv`), as for ISBN and DOI, and no spec validates it against a
schema.

## Why no data repo

arXiv holds about 2.5 million papers and adds about 20,000 a month, with
new versions of old papers every day. That is too large for a
`relaton-data-*` repo, and the API is free, stable and needs no key. The
`Db` cache keeps each fetched paper. If a data repo is wanted later, it
should harvest through OAI-PMH (arXiv's bulk channel) and key rows with
`Pubid::Arxiv`, as this flavor does.

## Tests

`spec/arxiv/`: `parser_spec.rb` reads committed Atom fixtures; three
`bibliography_spec.rb` examples replay VCR cassettes, and the error paths
use WebMock stubs. arXiv asks for 3 s between API calls: re-record by
running `spec/arxiv` alone.
