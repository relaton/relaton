describe Relaton::Ogc do
  before do
    allow_any_instance_of(Relaton::Index::Type).to receive(:actual?).and_return(false)
    allow_any_instance_of(Relaton::Index::FileIO).to receive(:check_file).and_return(nil)
  end

  it "has a version number" do
    expect(Relaton::Ogc::VERSION).not_to be_nil
  end

  it "returns grammar hash" do
    hash = Relaton::Ogc.grammar_hash
    expect(hash).to be_instance_of String
    expect(hash.size).to eq 32
  end

  it "fetch hit", vcr: "ogc_19_025r1" do
    hit_collection = Relaton::Ogc::Bibliography.search("OGC 19-025r1")
    expect(hit_collection.first).to be_instance_of Relaton::Ogc::Hit
    expect(hit_collection.first.item).not_to be_nil
  end

  it "fetches item lazily", vcr: "ogc_19_025r1" do
    hit = Relaton::Ogc::Hit.new({ code: "19-025r1", file: "data/19-025R1.yaml" }, nil)
    expect(hit.item).to be_instance_of Relaton::Ogc::ItemData
    expect(hit.item.docidentifier.first.content).to eq "19-025r1"
  end

  context "get code" do
    it "with edition", vcr: "ogc_19_025r1" do
      expect do
        result = Relaton::Ogc::Bibliography.get "OGC 19-025r1", nil, {}
        expect(result).not_to be_nil
        expect(result.docidentifier.first.content).to eq "19-025r1"
      end.to output(
        include("[relaton-ogc] INFO: (OGC 19-025r1) Fetching from Relaton repository ...",
                "[relaton-ogc] INFO: (OGC 19-025r1) Found: `19-025r1`"),
      ).to_stderr_from_any_process
    end

    it "with year", vcr: "ogc_19_025r1" do
      result = Relaton::Ogc::Bibliography.get "OGC 19-025r1", "2019", {}
      expect(result).not_to be_nil
      expect(result.docidentifier.first.content).to eq "19-025r1"
    end

    it "with wrong year", vcr: "ogc_19_025r1" do
      expect do
        result = Relaton::Ogc::Bibliography.get "OGC 19-025r1", "2018", {}
        expect(result).to be_nil
      end.to output(
        include("[relaton-ogc] INFO: (OGC 19-025r1) Not found.",
                "[relaton-ogc] INFO: (OGC 19-025r1) There was no match for `2018`"),
      ).to_stderr_from_any_process
    end

    it "ignore CC types", vcr: "ogc_12_128r14" do
      result = Relaton::Ogc::Bibliography.get "12-128r14", nil, {}
      expect(result).not_to be_nil
      expect(result.docidentifier.first.content).to eq "12-128r14"
    end

    it "returns doctype and subdoctype", vcr: "ogc_16_079" do
      result = Relaton::Ogc::Bibliography.get "16-079", nil, {}
      expect(result.ext.doctype.content).to eq "standard"
      expect(result.ext.subdoctype).to eq "implementation"
    end

    it "get OGC 15-043r3", vcr: "ogc_15_043r3" do
      result = Relaton::Ogc::Bibliography.get "OGC 15-043r3"
      expect(result).not_to be_nil
    end

    it "get document with unknown type", vcr: "ogc_09_048r5" do
      result = Relaton::Ogc::Bibliography.get "OGC 09-048r5"
      expect(result.ext.doctype.content).to eq "other"
    end

    it "handle empty reference" do
      result = Relaton::Ogc::Bibliography.get "OGC "
      expect(result).to be_nil
    end
  end
end
