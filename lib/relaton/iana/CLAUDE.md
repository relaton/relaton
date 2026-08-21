# CLAUDE.md

## Development

- `bundle install` — install dependencies
- `bundle exec rake spec:iana` — run this flavor's tests
  (rubocop is configured via the root `.rubocop.yml` but is not in the bundle)

## What this flavor is

IANA entries are protocol **registries**, not numbered standards. An identifier
is a hierarchical registry slug capped at one "/":

```
IANA _6lowpan-parameters
IANA _6lowpan-parameters/lowpan_nhc
```

`Parser#docnumber` builds the bare slug (`registry[/sub-registry]`) by joining a
nested registry's XML `id` to its parent's; `Core::DataFetcher#output_file`
turns that into the document filename (`data/_6lowpan-parameters-lowpan_nhc.yaml`).

`output_file` collapses `/` and `-` to the same character, so two distinct
registries can want one file — `rpki/signed-objects` and `rpki-signed-objects`
do, the only such pair in the 3405 published rows. `save_doc` therefore writes
through `Core::DataFetcher#unique_output_file`, which hands the second one a
digest-suffixed path instead of overwriting the first; the warning stays so the
clash is visible in the crawl log. Before that fix the corpus had 3405 index
rows over 3404 files, and one id resolved to the wrong document.

## Index (`index-v2`, pubid-keyed)

`INDEXFILE = "index-v2"` (`lib/relaton/iana.rb`). Rows carry
`Pubid::Iana::Identifiers::Registry` identifiers, serialized as:

```yaml
- :id:
    _type: pubid:iana:registry
    sub_registry: lowpan_nhc      # absent for a top-level registry
    number: _6lowpan-parameters
  :file: data/_6lowpan-parameters-lowpan_nhc.yaml
```

`number` holds the **top-level** slug — not a document number, because an IANA
identifier has none (digits only ever appear glued inside a slug token:
`sip-parameters/sip-parameters-13`, `idna-tables-11.0.0`). It is the index key:
`Relaton::Index::Type#candidates_by_number` bsearches on `id.root.number.to_s`,
so a registry and all of its sub-registries share one bucket (655 buckets over
the 3405 published rows; median 3, max 73 — `pcep`) and `Bibliography#pubid_match?`
separates them. `registry` is a **derived reader** over `number`, so it is not a
serialized key.

The triple that must stay in step, all passing
`pubid_class: ::Pubid::Iana::Identifier`:

| role | file |
|---|---|
| producer | `data_fetcher.rb` — `#index` + the guarded `#add_to_index` |
| consumer | `bibliography.rb` — `#index`, `#parse_ref`, `#pubid_match?` |
| processor | `processor.rb` — `#remove_index_file` |

`#add_to_index` rescues and warns rather than raising: `Relaton::Index` rejects
the **whole** index if one row fails to deserialize, so an unparseable slug has
to be skipped at write time instead of aborting the crawl.

### Why a stale index is loud, not silent

A row serialized before `number` existed (`{_type, registry, sub_registry}`)
deserializes with `number` **nil and no error at all**: lutaml ignores unknown
keys, and `Index::FileIO#id_supported?` skips its `to_hash`/`from_hash`
validation for a concrete subclass — which every IANA id is. pubid therefore
fails at *render* time instead: `Identifier#require_number!` raises
`ArgumentError` ("… regenerate the index") from `to_s`, `to_urn` and
`to_mr_string`. **If you see that error the index is stale — rebuild it, don't
work around it.** `spec/iana/relaton/iana_spec.rb`'s "the pubid index-v2
fixture" block is the tripwire for the fixture.

### Migration note (v1 → v2)

`index-v1` was keyed on the bare slug string, so `Index::Type#search` matched by
**substring** and `min_by { |i| i[:id] }` picked the shortest hit — `IANA rpki`
also matched `rpki/signed-objects`. v2 matches the identifier exactly, so a
partial reference no longer resolves.

This flavor no longer produces `index-v1`. `relaton-data-iana`'s own
`crawler.rb` derives it from `index-v2` (a plain YAML transform:
`sub_registry ? "#{number}/#{sub_registry}" : number`) so released gem lines
keep resolving.

## Testing

- **Framework:** RSpec with VCR cassettes and WebMock.
- **Index fixture:** `spec/iana/fixtures/index-v2.zip` (all 3405 published rows)
  is deserialized through `pubid_class` once per process and **re-seeded into
  the `Relaton::Index` pool before every example** — see
  `spec/iana/support/webmock.rb` for why (the producer-side `find_or_create`
  evicts it otherwise). Its `actual?` override claims only the consumer
  (`url:`) lookup.
- **VCR cassettes:** `spec/iana/vcr_cassettes/` — index downloads are ignored by
  VCR (`support/vcr.rb`), since the fixture answers them.
- The XML round-trip specs validate against `grammar/relaton-iana-compile.rng`
  with Jing, which needs a **Java runtime**; without one they fail with
  `Jing::ExecutionError`, unrelated to any code change.
