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
# The corpus is the suite's own committed index fixture — the ids
# `relaton-data-calconnect` publishes today. It runs offline; it is the check to
# re-run whenever the fixture is refreshed.

# Namespaced, and read once: a constant assigned inside an `RSpec.describe`
# block lands on Object, and this suite shares a process with the rest of
# spec/calconnect.
module CalconnectPublishedIds
  def self.all
    @all ||= Zip::File.open(
      File.join(__dir__, "..", "..", "fixtures",
                "#{Relaton::Calconnect::INDEXFILE_V1}.zip"),
    ) do |zip|
      YAML.safe_load(zip.first.get_input_stream.read, permitted_classes: [Symbol])
    end.map { |row| row[:id] }.freeze
  end

  def self.parsed
    @parsed ||= all.map { |id| ::Pubid::Calconnect::Identifier.parse id }.freeze
  end
end

RSpec.describe "the CalConnect index key" do
  let(:ids) { CalconnectPublishedIds.all }
  let(:pubids) { CalconnectPublishedIds.parsed }

  it "has a corpus worth measuring" do
    expect(ids.size).to be > 150
  end

  it "parses every published id" do
    unparseable = ids.filter_map do |id|
      ::Pubid::Calconnect::Identifier.parse id
      nil
    rescue StandardError => e
      "#{id} (#{e.message})"
    end
    expect(unparseable).to be_empty
  end

  it "renders one distinct key per row" do
    expect(pubids.map(&:to_s).uniq.size).to eq ids.size
  end

  # The document's own printed id and the index key are the same string for this
  # flavor, so `to_s` has to reproduce the source exactly. If it ever stops, the
  # v1 index derived in relaton-data-calconnect stops matching the published one.
  it "round-trips to_s back to the published string" do
    expect(pubids.map(&:to_s)).to eq ids
  end

  it "round-trips every row through to_hash/from_hash" do
    rebuilt = pubids.map { |p| ::Pubid::Calconnect::Identifier.from_hash p.to_hash }
    expect(rebuilt.map(&:to_s)).to eq ids
  end

  it "never keys the index bsearch on an empty number" do
    expect(pubids.map { |p| p.root.number.to_s }).to all(satisfy { |n| !n.empty? })
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

    # The two collision risks the corpus actually contains.
    it "keeps two series with one number apart" do
      expect(pubid("CC/CD 51016:2018")).not_to eq pubid("CC/WD 51016:2018")
    end

    it "keeps two years of one document apart" do
      expect(pubid("CC/S 0601:2005")).not_to eq pubid("CC/S 0601:2006")
    end
  end

  # The narrowing the consumer will do: ignore exactly what the reference left
  # out. `series` is never ignorable — it is what tells CC/CD from CC/WD.
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
