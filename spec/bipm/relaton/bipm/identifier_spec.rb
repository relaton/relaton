describe Relaton::Bipm::ItemData do
  def item_with(content)
    docid = Relaton::Bib::Docidentifier.new(content: content, type: "BIPM", primary: true)
    described_class.new(docidentifier: [docid])
  end

  describe "docidentifier #to_s(form:)" do
    it "drops the BIPM prefix in the internal form" do
      docid = item_with("BIPM SI Brochure Part 1").docidentifier.first
      expect(docid.to_s(form: :external)).to eq "BIPM SI Brochure Part 1"
      expect(docid.to_s(form: :internal)).to eq "SI Brochure Part 1"
    end

    it "keeps a committee identifier, which has no prefix" do
      expect(item_with("CGPM RES (1889)").docidentifier.first.to_s(form: :internal))
        .to eq "CGPM RES (1889)"
    end

    it "drops the prefix of the English docidentifier of an item from YAML" do
      item = Relaton::Bipm::Item.from_yaml File.read("fixtures/data/si-brochure.yaml")
      docid = item.docidentifier.find { |d| d.language == "en" }
      expect(docid.to_s(form: :internal)).to eq "SI Brochure Part 1"
    end

    it "drops the prefix of a relation item after a YAML round trip" do
      item = item_with("CIPM RES (1879)")
      item.relation = [Relaton::Bib::Relation.new(type: "hasPart", bibitem: item_with("BIPM SI Brochure"))]
      related = Relaton::Bipm::Item.from_yaml(item.to_yaml).relation.first.bibitem
      expect(related.docidentifier.first.to_s(form: :internal)).to eq "SI Brochure"
    end
  end
end
