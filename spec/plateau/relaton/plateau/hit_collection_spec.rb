RSpec.describe Relaton::Plateau::HitCollection do
  let(:index) { double("Index") }

  before do
    expect(Relaton::Index).to receive(:find_or_create).with(
      :plateau,
      pages_url: Relaton::Plateau::PAGES_URL,
      pubid_class: ::Pubid::Plateau::Identifier
    ).and_return(index)
  end

  describe "#find" do
    it "finds exact match" do
      row = { id: "PLATEAU Handbook #01 第2.0版", file: "data/plateau-handbook-01-20.yaml" }
      expect(index).to receive(:search)
        .with(Pubid::Plateau.parse("PLATEAU Handbook #01 第2.0版"), exact: true)
        .and_return([row])

      collection = described_class.new("PLATEAU Handbook #01 第2.0版").find
      expect(collection).to be_instance_of described_class
      expect(collection.size).to eq 1
      expect(collection.first).to be_instance_of Relaton::Plateau::Hit
    end

    it "finds all editions" do
      rows = [
        { id: "PLATEAU Handbook #01 第2.0版", file: "data/plateau-handbook-01-20.yaml" },
        { id: "PLATEAU Handbook #01 第1.0版", file: "data/plateau-handbook-01-10.yaml" },
      ]
      expect(index).to receive(:search)
        .with(Pubid::Plateau.parse("PLATEAU Handbook #01")).and_return(rows)

      collection = described_class.new("PLATEAU Handbook #01").find
      expect(collection.size).to eq 2
    end

    it "returns empty when no match" do
      expect(index).to receive(:search).and_return([])

      collection = described_class.new("PLATEAU Handbook #99 第1.0版").find
      expect(collection.size).to eq 0
    end
  end

  describe "#fetch_doc" do
    it "returns nil when empty" do
      expect(index).to receive(:search).and_return([])

      result = described_class.new("PLATEAU Handbook #99 第1.0版").find.fetch_doc
      expect(result).to be_nil
    end

    it "returns item for single edition" do
      row = { id: "PLATEAU Handbook #01 第2.0版", file: "data/plateau-handbook-01-20.yaml" }
      expect(index).to receive(:search).and_return([row])

      yaml = File.read "fixtures/item.yaml", encoding: "UTF-8"
      response = double(Net::HTTPResponse, code: "200", body: yaml)
      expect(Net::HTTP).to receive(:get_response).and_return(response)

      result = described_class.new("PLATEAU Handbook #01 第2.0版").find.fetch_doc
      expect(result.docidentifier.first.content).to eq "PLATEAU Handbook #00 1.0"
    end

    it "returns item with hasEdition relations for all editions" do
      rows = [
        { id: "PLATEAU Handbook #00 第2.0版", file: "data/plateau-handbook-00-20.yaml" },
        { id: "PLATEAU Handbook #00 第1.0版", file: "data/plateau-handbook-00-10.yaml" },
      ]
      expect(index).to receive(:search).and_return(rows)

      yaml = File.read "fixtures/item.yaml", encoding: "UTF-8"
      response = double(Net::HTTPResponse, code: "200", body: yaml)
      expect(Net::HTTP).to receive(:get_response).twice.and_return(response)

      result = described_class.new("PLATEAU Handbook #00").find.fetch_doc
      expect(result).to be_instance_of Relaton::Plateau::ItemData
      expect(result.relation.size).to eq 2
      expect(result.relation.first.type).to eq "hasEdition"
      expect(result.docidentifier.first.content).to eq "PLATEAU Handbook #00"
    end

    it "strips the volume label with the edition from the family id" do
      rows = [
        { id: "PLATEAU Handbook #00 第6.0版 本編＋付録", file: "data/plateau-handbook-00-60-with-appendix.yaml" },
        { id: "PLATEAU Handbook #00 第5.0版 本編", file: "data/plateau-handbook-00-50-main.yaml" },
      ]
      expect(index).to receive(:search).and_return(rows)

      yaml = File.read("fixtures/item.yaml", encoding: "UTF-8")
        .gsub("Handbook #00 1.0", "Handbook #00 第6.0版 本編＋付録")
      response = double(Net::HTTPResponse, code: "200", body: yaml)
      expect(Net::HTTP).to receive(:get_response).twice.and_return(response)

      result = described_class.new("PLATEAU Handbook #00").find.fetch_doc
      expect(result.docidentifier.first.content).to eq "PLATEAU Handbook #00"
      expect(result.docnumber).to eq "Handbook #00"
    end

    it "returns single item when all editions has only one result" do
      row = { id: "PLATEAU Handbook #00 第1.0版", file: "data/plateau-handbook-00-10.yaml" }
      expect(index).to receive(:search).and_return([row])

      yaml = File.read "fixtures/item.yaml", encoding: "UTF-8"
      response = double(Net::HTTPResponse, code: "200", body: yaml)
      expect(Net::HTTP).to receive(:get_response).and_return(response)

      result = described_class.new("PLATEAU Handbook #00").find.fetch_doc
      expect(result.docidentifier.first.content).to eq "PLATEAU Handbook #00 1.0"
    end
  end

  describe "#index" do
    it "creates index with correct parameters" do
      collection = described_class.new("PLATEAU Handbook #01 第1.0版")
      expect(collection.index).to eq index
    end
  end
end

# The rows `#find` selects from the committed index fixture. pubid declares
# `annex` strict for PLATEAU, so a reference without an annex means the
# document itself, not "any annex".
RSpec.describe Relaton::Plateau::HitCollection, "against the index fixture" do
  let(:fixture_index) do
    yaml = Zip::File.open(INDEX_ZIP_PATH) { |zip| zip.first.get_input_stream.read }
    file = File.join(Dir.mktmpdir("relaton-plateau-spec"), "index-v2.yaml")
    File.write(file, yaml)
    Relaton::Index::Type.new(:plateau, file: file, pubid_class: ::Pubid::Plateau::Identifier)
  end

  before do
    allow(Relaton::Index).to receive(:find_or_create).and_return(fixture_index)
  end

  def ids(ref)
    described_class.new(ref).find.map { |hit| hit.hit[:id].to_s }.sort
  end

  it "does not answer a reference without an annex with an annex" do
    expect(ids("PLATEAU Handbook #03")).to eq [
      "PLATEAU Handbook #03 第1.0版", "PLATEAU Handbook #03 第2.0版",
      "PLATEAU Handbook #03 第3.0版", "PLATEAU Handbook #03 第4.0版"
    ]
  end

  it "finds every edition of an annex" do
    expect(ids("PLATEAU Handbook #03-1")).to eq [
      "PLATEAU Handbook #03-1 第1.0版", "PLATEAU Handbook #03-1 第2.0版",
      "PLATEAU Handbook #03-1 第3.0版"
    ]
  end

  it "finds one edition of the document" do
    expect(ids("PLATEAU Handbook #03 第3.0版")).to eq ["PLATEAU Handbook #03 第3.0版"]
  end

  # pubid declares `volume` strict for PLATEAU: a reference without a volume
  # means "no volume" to `===`. An edition-less reference asks for every
  # edition, so it must reach every volume too.
  context "when the editions have volume labels" do
    let(:volumes) do
      ["PLATEAU Handbook #00 第6.0版 本編＋付録", "PLATEAU Handbook #00 第5.0版 本編",
       "PLATEAU Handbook #00 第5.0版 本編＋付録"]
    end

    before do
      volumes.each { |id| fixture_index.add_or_update ::Pubid::Plateau.parse(id), "data/x.yaml" }
    end

    it "finds every volume of every edition" do
      expect(ids("PLATEAU Handbook #00")).to include(*volumes, "PLATEAU Handbook #00 第1.0版")
    end

    it "finds one volume of one edition" do
      expect(ids("PLATEAU Handbook #00 第5.0版 本編")).to eq ["PLATEAU Handbook #00 第5.0版 本編"]
    end

    it "does not answer a reference without an annex with an annex volume" do
      expect(ids("PLATEAU Handbook #03")).not_to include(a_string_matching(/#03-1/))
    end
  end
end
