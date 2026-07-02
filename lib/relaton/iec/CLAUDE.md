# CLAUDE.md

## Development

- `bundle install` — install dependencies
- `bundle exec rake spec` — run tests
- `bundle exec rubocop` — lint

## Testing

- **Framework:** RSpec with VCR cassettes and WebMock
- **Index fixture:** `spec/fixtures/index-v2.zip` is pre-loaded into `Relaton::Index` pool in `before(:suite)` (configured in `spec/support/webmock.rb`). Run `rake spec:update_index` to refresh from relaton-data-iec. The fixture is the lean pubid-v2 `to_hash` index (`_type`-tagged rows); rows are deserialized via `Pubid::Iec::Identifier.from_hash` and validated by round-trip in relaton-index (no `id_keys` allowlist).
- **VCR cassettes:** `spec/vcr_cassettes/` — index download requests are ignored by VCR (handled by fixture).
