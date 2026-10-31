require "tmpdir"

RSpec.describe Relaton::Nist::Cswp do
  describe ".normalize" do
    {
      "NIST CSWP 6 spa" => "CSWP 6 SPA",
      "NIST CSWP 6(spa)" => "CSWP 6 SPA",
      "NIST.CSWP.6.spa" => "CSWP 6 SPA",
      "NIST CSWP 01142020" => "CSWP 01142020",
      "NIST.CSWP.02042020-2" => "CSWP 02042020-2",
      "NIST CSWP 01162020es" => "CSWP 01162020ES",
      "nist cswp 6 spa" => "CSWP 6 SPA",
    }.each do |ref, key|
      it "reads #{ref.inspect} as #{key.inspect}" do
        expect(described_class.normalize(ref)).to eq key
      end
    end
  end

  describe ".lookup" do
    it "maps a legacy dated id to the numbered id" do
      expect(described_class.lookup("NIST.CSWP.01142020")).to eq [:legacy, "NIST CSWP 9", "NIST CSWP 01142020"]
    end

    it "keeps a stage of the numbered id" do
      expect(described_class.lookup("NIST CSWP 06222021-draft")).to eq(
        [:legacy, "NIST CSWP 19 ipd", "NIST CSWP 06222021-draft"],
      )
    end

    it "maps a dated translation to the numbered translation" do
      type, entry = described_class.lookup("NIST CSWP 04162018ar")
      expect(type).to eq :translation
      expect(entry[:id]).to eq "6 ara"
    end

    it "finds a translation in each spelling" do
      ["NIST CSWP 6 spa", "NIST CSWP 6(spa)", "NIST.CSWP.6.spa"].each do |ref|
        type, entry = described_class.lookup(ref)
        expect(type).to eq :translation
        expect(entry[:id]).to eq "6 spa"
      end
    end

    it "answers nil for a numbered CSWP that CSRC lists" do
      expect(described_class.lookup("NIST CSWP 9")).to be_nil
    end

    it "answers nil for an EO Response id with no numbered match" do
      expect(described_class.lookup("NIST CSWP 02042022-1")).to be_nil
    end

    it "answers nil for another series" do
      expect(described_class.lookup("NIST SP 800-53r5")).to be_nil
    end
  end

  describe "table" do
    let(:csrc_ids) do
      Relaton::Nist::PubsExport.instance.data.filter_map do |row|
        row["docidentifier"] if row["docidentifier"].to_s.start_with?("CSWP ")
      end
    end

    it "points every legacy id to a translation or a CSWP that CSRC lists" do
      described_class.table["legacy"].each_value do |target|
        next if described_class.table["translations"].key?(target)

        expect(csrc_ids).to include("CSWP #{target.sub(/ ipd\z/, '')}")
      end
    end

    it "keys a translation by an original that CSRC lists" do
      described_class.table["translations"].each_key do |key|
        expect(csrc_ids).to include("CSWP #{key.split.first}")
      end
    end
  end

  describe ".translation_item" do
    subject(:item) { described_class.translation_item(described_class.lookup("NIST CSWP 6 spa")[1]) }

    it "carries the translation id and the DOI" do
      expect(item.docidentifier.map { |d| [d.type, d.content, d.primary] }).to eq [
        ["NIST", "NIST CSWP 6(spa)", true], ["DOI", "NIST.CSWP.6.spa", nil]
      ]
    end

    it "carries the RIS title, year, author and language" do
      expect(item.title.first.content).to eq(
        "Framework for Improving Critical Infrastructure Cybersecurity, Version 1.1 (Spanish translation)",
      )
      expect(item.date.map { |d| [d.type, d.at.to_s] }).to eq [%w[published 2018]]
      author = item.contributor.find { |c| c.role.first.type == "author" }
      expect(author.person.name.surname.content).to eq "Stine"
      expect(author.person.name.forename.first.content).to eq "Kevin"
      expect(item.language).to eq ["es"]
      expect(item.script).to eq ["Latn"]
    end

    it "relates to the original" do
      rel = item.relation.first
      expect(rel.type).to eq "translatedFrom"
      expect(rel.bibitem.docidentifier.first.content).to eq "NIST CSWP 6"
    end

    it "links the DOI" do
      expect(item.source.map { |s| [s.type, s.content.to_s] }).to eq [
        ["doi", "https://doi.org/10.6028/NIST.CSWP.6.spa"],
      ]
    end

    it "validates against the NIST grammar" do
      Dir.mktmpdir do |dir|
        file = File.join dir, "cswp.xml"
        File.write file, Relaton::Nist::Bibitem.to_xml(item), encoding: "UTF-8"
        schema = Relaxng.new "../../grammar/relaton-nist-compile.rng"
        expect(schema.validate(file)).to eq []
      end
    end

    it "round-trips through YAML" do
      yaml = Relaton::Nist::Item.to_yaml(item)
      expect(Relaton::Nist::Item.from_yaml(yaml).docidentifier.first.content).to eq "NIST CSWP 6(spa)"
    end

    it "uses the script of the language" do
      jpn = described_class.translation_item(described_class.lookup("NIST CSWP 6 jpn")[1])
      expect(jpn.language).to eq ["ja"]
      expect(jpn.script).to eq ["Jpan"]
    end
  end
end
