# frozen_string_literal: true

# Regression guard for the pubid `Identifiers::Base` -> `Identifier` migration.
# `Pubid::Iho::Identifier` is the deserialization root passed as `pubid_class:`
# for the IHO index (bibliography.rb, spec/iho/support/webmock.rb). Newer pubid
# drops the old `Pubid::Iho::Identifiers::Base` alias, so naming it would
# NameError at index load; this pins the canonical handle and its from_hash
# dispatch.
describe "Pubid::Iho::Identifier" do
  it "is the shared pubid identifier root" do
    expect(defined?(::Pubid::Iho::Identifier)).to eq "constant"
    expect(::Pubid::Iho::Identifier.ancestors).to include(::Pubid::Identifier)
  end

  it "deserializes an IHO index `_type:` row into a concrete IHO identifier" do
    row = { "_type" => "pubid:iho:miscellaneous", "number" => "1", "version" => "2.1.0" }
    id = ::Pubid::Iho::Identifier.from_hash(row)
    expect(id).to be_a ::Pubid::Iho::Identifier
    expect(id.number).to eq "1"
  end
end
