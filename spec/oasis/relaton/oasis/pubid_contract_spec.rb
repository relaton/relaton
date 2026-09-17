# frozen_string_literal: true

require "tmpdir"

# The pubid assumptions the OASIS `index-v2` producer rests on. Each example
# names one property that, if pubid lost it, would corrupt a crawl silently
# rather than fail it. The `number` examples guard the index key that pubid
# `cfe8ee84` added by renaming `spec` -> `number`: before it every row keyed on
# `""` and the bsearch degraded to a full scan, with nothing failing.
RSpec.describe "Pubid::Oasis contract" do
  # One id of each observed shape: bare slug, version + stage + part, a
  # lowercase version, an errata suffix, and a "Part" spelling.
  let(:ids) do
    ["OASIS amqp-core",
     "OASIS OSLC-CoreShapes-3.0-PS01-Pt8",
     "OASIS mqtt-v5.0",
     "OASIS ubl-2.3-Errata01",
     "OASIS CAM-v1.0-Part1"]
  end

  it "parses every shape" do
    ids.each do |id|
      expect { Pubid::Oasis::Identifier.parse(id) }.not_to raise_error
    end
  end

  it "renders the slug back verbatim" do
    ids.each do |id|
      expect(Pubid::Oasis::Identifier.parse(id).to_s).to eq id
    end
  end

  it "round-trips through to_hash / from_hash" do
    ids.each do |id|
      pubid = Pubid::Oasis::Identifier.parse id
      restored = Pubid::Identifier.from_hash pubid.to_hash
      expect(restored).to be_a Pubid::Oasis::Identifiers::Standard
      expect(restored.to_s).to eq id
    end
  end

  # `Relaton::Index::Type#candidates_by_number` bsearches on this exact key, and
  # `FileIO` sorts the index by it. An empty key puts every row in one bucket
  # and degrades the search to a full scan, silently.
  describe "the index key" do
    it "is never empty" do
      keys = ids.map { |id| Pubid::Oasis::Identifier.parse(id).root.number.to_s }
      expect(keys).to all satisfy { |key| !key.empty? }
    end

    it "holds the specification name, so a spec's versions cluster" do
      keys = ["OASIS OSLC-CoreShapes-3.0-PS01-Pt8",
              "OASIS OSLC-CoreShapes-2.0"].map do |id|
        Pubid::Oasis::Identifier.parse(id).root.number.to_s
      end
      expect(keys).to eq %w[OSLC-CoreShapes OSLC-CoreShapes]
    end

    it "survives a store-and-reload through Relaton::Index" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "index-v2.yaml")
        written = index_type file
        ids.each_with_index do |id, i|
          written.add_or_update Pubid::Oasis::Identifier.parse(id), "data/#{i}.yaml"
        end
        written.save

        rows = index_type(file).index
        expect(rows.map { |r| r[:id] })
          .to all be_a Pubid::Oasis::Identifiers::Standard
        expect(rows.map { |r| r[:id].root.number.to_s })
          .to all satisfy { |key| !key.empty? }
        expect(rows.map { |r| r[:id].to_s }.sort).to eq ids.sort
      end
    end

    def index_type(file)
      Relaton::Index::Type.new(
        :oasis_contract, nil, file, nil, ::Pubid::Oasis::Identifier
      )
    end
  end

  # `Bibliography#find_index_entry` selects rows with pubid's asymmetric subset
  # match: the reference on the left, the row on the right. A component the
  # reference omits matches any value; a component it states must be equal. The
  # direction is the whole contract, so both directions are asserted.
  context "subset match" do
    def id(ref) = Pubid::Oasis::Identifier.parse(ref)

    it "lets a reference reach a row that states more" do
      expect(id("OASIS STIX") === id("OASIS STIX-v2.1-CS02")).to be true
    end

    it "is not symmetric" do
      expect(id("OASIS STIX-v2.1-CS02") === id("OASIS STIX")).to be false
    end

    it "keeps a fully stated reference on its own row" do
      expect(id("OASIS STIX-v2.1-CS02") === id("OASIS STIX-v2.1-CS01"))
        .to be false
    end
  end
end
