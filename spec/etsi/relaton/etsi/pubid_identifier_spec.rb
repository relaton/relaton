# frozen_string_literal: true

# Regression guard for the pubid `Identifiers::Base` -> `Identifier` migration.
# `Pubid::Etsi::Identifier` is the deserialization root passed as `pubid_class:`
# for the ETSI index-v2 (bibliography.rb, data_fetcher.rb, processor.rb,
# spec/etsi/support/webmock.rb). Newer pubid drops the old
# `Pubid::Etsi::Identifiers::Base` alias, so naming it would NameError at index
# load; this pins the canonical handle and its from_hash dispatch.
describe "Pubid::Etsi::Identifier" do
  it "is the shared pubid identifier root" do
    expect(defined?(::Pubid::Etsi::Identifier)).to eq "constant"
    expect(::Pubid::Etsi::Identifier.ancestors).to include(::Pubid::Identifier)
  end

  it "deserializes an ETSI index `_type:` row into a concrete ETSI identifier" do
    row = { "_type" => "pubid:etsi:etsi-standard", "type" => "GR",
            "number" => "ZSM 021", "version" => "1.1.1", "year" => "2026", "month" => "05" }
    id = ::Pubid::Etsi::Identifier.from_hash(row)
    expect(id).to be_a ::Pubid::Etsi::Identifier
    expect(id.type).to eq "GR"
  end
end
