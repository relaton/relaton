require "relaton/ecma"
require "zip"
require "yaml"

# The property the pubid `index-v2` stands or falls on.
#
# `Relaton::Index::Type#add_or_update` keys on a BARE `id.to_s`, so an id that
# does not render its edition collapses every edition of a document onto one key
# and the crawl reports success while dropping the rest. Measured over the
# published index that was 383 of 804 rows.
#
# The check runs offline over the suite's own index fixture, which is a copy of
# the published `relaton-data-ecma` index — the same corpus, no network.
module EcmaIndexCorpus
  # The published corpus, as the suite's own fixture holds it.
  ROWS = Zip::File.open(
    File.join(__dir__, "..", "..", "fixtures",
              "#{Relaton::Ecma::INDEXFILE_V1}.zip"),
  ) { |zip| YAML.safe_load zip.first.get_input_stream.read, permitted_classes: [Symbol] }.freeze

  # The three model fields DataFetcher#index_id assembles, as the v1 index
  # stored them.
  def self.identifier(row)
    id = ::Pubid::Ecma::Identifier.parse row[:id][:id]
    id.edition = row[:id][:ed] if row[:id][:ed]
    id.volume = row[:id][:vol] if row[:id][:vol]
    id
  end

  IDS = ROWS.map { |row| identifier(row) }.freeze
end

RSpec.describe "the ECMA index key" do
  let(:rows) { EcmaIndexCorpus::ROWS }
  let(:ids) { EcmaIndexCorpus::IDS }

  it "has a corpus worth measuring" do
    expect(rows.size).to be > 700
    expect(rows.count { |r| r[:id][:ed] }).to be > 700
    expect(rows.count { |r| r[:id][:vol] }).to eq 4
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
    expect(ids.map { |id| id.root.number.to_s }).to all(be_truthy & satisfy { |n| !n.empty? })
  end

  it "round-trips every row through to_hash/from_hash" do
    expect(ids.all? { |id| ::Pubid::Ecma::Identifier.from_hash(id.to_hash) == id }).to be true
  end

  it "renders the bare document form without the two index components" do
    # What Relaton::Ecma::Docidentifier stores as `content`.
    bare = ids.map { |id| id.to_s(with_edition: false, with_volume: false) }
    expect(bare.uniq.size).to eq rows.map { |r| r[:id][:id] }.uniq.size
  end
end
