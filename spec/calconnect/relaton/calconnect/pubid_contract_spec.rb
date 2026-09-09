require "relaton/calconnect"
require "yaml"
require "zip"

# The properties the pubid `index-v2` stands or falls on, measured over the whole
# published corpus rather than a handful of chosen ids.
#
# `Relaton::Index::Type#add_or_update` keys on a BARE `id.to_s`, so two ids that
# render alike collapse onto one row and the crawl reports success while dropping
# the other. `Type#candidates_by_number` then bsearches on `id.root.number.to_s`,
# so an empty key would bucket the whole index together and silently degrade the
# search back to a full scan. And `Relaton::Index` rejects the WHOLE index if a
# single row fails to deserialize, so `from_hash(to_hash)` has to hold for every
# row, not most of them.
#
# The corpus is `index-v2.zip`, the suite's verbatim copy of the published
# index — the same rows the runtime deserializes. It runs offline; re-run it
# whenever the fixture is refreshed.
#
# The legacy `index-v1` is deliberately NOT a fixture here. It exists only for
# released relaton v2 clients, and `relaton-data-calconnect` builds it from each
# crawled document's own docidentifier rather than from these rows, so this gem
# neither produces it nor reads it and has nothing to assert about it.

module CalconnectFixtures
  # The runtime rows: v2 hashes deserialized exactly as Relaton::Index does.
  def self.identifiers
    @identifiers ||= Zip::File.open(
      File.join(__dir__, "..", "..", "fixtures",
                "#{Relaton::Calconnect::INDEXFILE}.zip"),
    ) do |zip|
      YAML.safe_load zip.first.get_input_stream.read, permitted_classes: [Symbol]
    end.map { |row| ::Pubid::Calconnect::Identifier.from_hash row[:id] }.freeze
  end
end

RSpec.describe "the CalConnect index key" do
  let(:pubids) { CalconnectFixtures.identifiers }

  it "has a corpus worth measuring" do
    expect(pubids.size).to be > 150
  end

  it "deserializes every row into an identifier, not a raw hash" do
    expect(pubids).to all(be_a(::Pubid::Calconnect::Identifier))
  end

  it "renders one distinct key per row" do
    expect(pubids.map(&:to_s).uniq.size).to eq pubids.size
  end

  it "never keys the index bsearch on an empty number" do
    expect(pubids.map { |p| p.root.number.to_s }).to all(satisfy { |n| !n.empty? })
  end

  it "round-trips every row through to_hash/from_hash" do
    rebuilt = pubids.map { |p| ::Pubid::Calconnect::Identifier.from_hash p.to_hash }
    expect(rebuilt.map(&:to_s)).to eq pubids.map(&:to_s)
  end

  # The renderer and the parser have to agree: `HitCollection` parses a
  # reference and compares it against these rows, so a row whose own rendered
  # form no longer parses back to it would be unreachable by its own id.
  it "parses every rendered key back to the same identifier" do
    mismatched = pubids.filter_map do |id|
      back = ::Pubid::Calconnect::Identifier.parse id.to_s
      back.to_s == id.to_s ? nil : "#{id} -> #{back}"
    rescue StandardError => e
      "#{id} (#{e.message})"
    end
    expect(mismatched).to be_empty
  end

  # The shapes that would break a naive grammar, each present in the corpus.
  context "edge shapes" do
    def pubid(id) = ::Pubid::Calconnect::Identifier.parse(id)

    it "keeps a leading zero in the number" do
      expect(pubid("CC/A 0001:2000").number).to eq "0001"
    end

    it "keeps a dashed sub-number in one token" do
      expect(pubid("CC/A 0812-1:2008").number).to eq "0812-1"
    end

    it "keeps a dotted sub-number in one token" do
      expect(pubid("CC/Adv 0707.1:2007").number).to eq "0707.1"
    end

    it "parses a full date, not just a year" do
      id = pubid("CC/WD 51017:2024-07-23")
      expect([id.date.year, id.date.month, id.date.day]).to eq %w[2024 07 23]
      expect(id.to_hash).to include("year" => "2024", "month" => "07", "day" => "23")
    end

    it "parses a series-less id" do
      expect(pubid("CC 18011:2018").series).to be_nil
    end

    # The three collision risks the corpus actually contains.
    it "keeps two series with one number apart" do
      expect(pubid("CC/CD 51016:2018")).not_to eq pubid("CC/WD 51016:2018")
    end

    it "keeps a series-less id apart from a seried one" do
      expect(pubid("CC 36010:2026")).not_to eq pubid("CC/WD 36010:2019")
    end

    it "keeps two years of one document apart" do
      expect(pubid("CC/S 0601:2005")).not_to eq pubid("CC/S 0601:2006")
    end
  end

  # The narrowing the consumer does: ignore exactly what the reference left out.
  context "matches?" do
    def pubid(id) = ::Pubid::Calconnect::Identifier.parse(id)

    it "reaches every year of a document from an undated reference" do
      ref = pubid "CC/S 0601"
      expect(ref.matches?(pubid("CC/S 0601:2005"), ignore: [:year])).to be true
      expect(ref.matches?(pubid("CC/S 0601:2006"), ignore: [:year])).to be true
    end

    it "reaches a fully dated row from an undated reference" do
      expect(pubid("CC/WD 51017").matches?(pubid("CC/WD 51017:2024-07-23"), ignore: [:year]))
        .to be true
    end

    it "never matches across series" do
      expect(pubid("CC/CD 51016").matches?(pubid("CC/WD 51016:2018"), ignore: [:year]))
        .to be false
    end

    it "never matches across numbers" do
      expect(pubid("CC/DIR 10005").matches?(pubid("CC/DIR 10006:2019"), ignore: [:year]))
        .to be false
    end
  end
end
