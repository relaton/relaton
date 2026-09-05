require "relaton/ecma"

# The property the pubid `index-v2` stands or falls on.
#
# `Relaton::Index::Type#add_or_update` keys on a BARE `id.to_s`, so an id that
# does not render its edition collapses every edition of a document onto one key
# and the crawl reports success while dropping the rest. Measured over the
# published index that was 383 of 804 rows.
#
# The check runs offline over the suite's own index fixture, which is a verbatim
# copy of the published `relaton-data-ecma` `index-v2.zip` — the same rows the
# runtime deserializes, no network.
RSpec.describe "the ECMA index key" do
  # The pooled fixture, deserialized through `pubid_class:` exactly as
  # Bibliography#index does.
  let(:rows) { EcmaIndexFixture.index_type.index }
  let(:ids) { rows.map { |row| row[:id] } }

  it "has a corpus worth measuring" do
    expect(rows.size).to be > 700
    expect(ids.count(&:edition)).to be > 700
    expect(ids.count(&:volume)).to eq 4
  end

  it "deserializes every row into an identifier, not a raw hash" do
    # `Relaton::Index` rejects the WHOLE index on the first row it cannot
    # rebuild, so a clean load over all rows is the real test.
    expect(ids).to all(be_a(::Pubid::Ecma::Identifier))
  end

  it "renders one distinct key per row" do
    expect(ids.map(&:to_s).uniq.size).to eq rows.size
  end

  it "keeps the four ECMA-269 edition-3 volumes apart" do
    # They share a docidentifier AND a title, so the volume is the only thing
    # that distinguishes them.
    keys = ids.select { |id| id.number == "269" && id.edition == "3" }.map(&:to_s)
    expect(keys).to contain_exactly(
      "ECMA-269 ed3 vol1", "ECMA-269 ed3 vol2",
      "ECMA-269 ed3 vol3", "ECMA-269 ed3 vol4"
    )
  end

  it "never keys the index bsearch on an empty number" do
    # `Type#candidates_by_number` bsearches on `id.root.number.to_s`; an empty
    # one puts every row in a single bucket and degrades the search silently.
    expect(ids.map { |id| id.root.number.to_s }).to all(satisfy { |n| !n.empty? })
  end

  it "is sorted, so the bsearch is valid" do
    expect(EcmaIndexFixture.index_type.instance_variable_get(:@file_io).sorted).to be true
  end

  it "round-trips every row through to_hash/from_hash" do
    expect(ids.all? { |id| ::Pubid::Ecma::Identifier.from_hash(id.to_hash) == id }).to be true
  end

  it "renders the bare document form without the two index components" do
    # What Relaton::Ecma::Docidentifier stores as `content`: 804 index rows,
    # 421 distinct documents.
    bare = ids.map { |id| id.to_s(with_edition: false, with_volume: false) }
    expect(bare.uniq.size).to be < rows.size
    expect(bare).to all(satisfy { |s| !s.include?(" ed") && !s.include?(" vol") })
  end
end
