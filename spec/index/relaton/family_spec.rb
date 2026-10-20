# frozen_string_literal: true

require "tmpdir"
require "pubid"

describe "Relaton::Index::Type#family" do
  # A pubid-backed index seeded with one document's editions and parts.
  let(:docids) do
    ["ISO 1", "ISO 1:2015", "ISO 1:2020", "ISO 1-1:2015"].map do |ref|
      Pubid::Iso::Identifier.parse(ref)
    end
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @file = File.join(dir, "index.yaml")
      rows = docids.map { |id| { id: id.to_hash, file: "#{id}.yaml" } }
      File.write(@file, rows.to_yaml)
      example.run
    end
  end

  subject(:index) do
    Relaton::Index::Type.new(:iso, file: @file,
                                      pubid_class: Pubid::Iso::Identifier)
  end

  it "collects every row sharing the reference's root number" do
    family = index.family("ISO 1")

    expect(family.root_number).to eq("1")
    expect(family.members.map { |row| row[:id].to_s }.sort)
      .to eq(["ISO 1", "ISO 1-1:2015", "ISO 1:2015", "ISO 1:2020"])
  end

  it "groups the editions by their stated year" do
    editions = index.family("ISO 1").editions

    expect(editions.keys).to eq(%w[2015 2020])
    expect(editions["2015"].map { |row| row[:id].to_s })
      .to contain_exactly("ISO 1:2015", "ISO 1-1:2015")
  end

  it "groups the parts by their stated part" do
    parts = index.family("ISO 1").parts

    expect(parts.keys).to eq(["1"])
    expect(parts["1"].map { |row| row[:id].to_s }).to eq(["ISO 1-1:2015"])
  end

  it "accepts a parsed reference as well as a string" do
    parsed = Pubid::Iso::Identifier.parse("ISO 1:2020")

    expect(index.family(parsed).members.size).to eq(4)
  end

  it "returns an empty family for a root the index does not hold" do
    family = index.family("ISO 2")

    expect(family.members).to be_empty
    expect(family.editions).to be_empty
    expect(family.parts).to be_empty
  end

  it "refuses a String reference on a pubid-less index" do
    plain = Relaton::Index::Type.new(:iso, file: @file)

    expect { plain.family("ISO 1") }
      .to raise_error(ArgumentError, /pubid-backed/)
  end
end
