describe Relaton::Nist::Docidentifier do
  def build_docid(content, type: "NIST", primary: true)
    described_class.new(content: content, type: type, primary: primary)
  end

  context "with a parseable NIST identifier" do
    subject(:docid) { build_docid("NIST SP 800-53r5") }

    it "parses the content into a Pubid::Nist::Identifier" do
      expect(docid.pubid).to be_a(::Pubid::Nist::Identifier)
    end

    it "round-trips the canonical string via #content and #to_s" do
      expect(docid.content).to eq "NIST SP 800-53r5"
      expect(docid.to_s).to eq "NIST SP 800-53r5"
    end
  end

  context "with a supplement/circular identifier" do
    subject(:docid) { build_docid("NBS CIRC 25sup") }

    it "parses and round-trips" do
      expect(docid.pubid).to be_a(::Pubid::Nist::Identifier)
      expect(docid.content).to eq "NBS CIRC 25sup"
    end
  end

  describe "#remove_part!" do
    it "drops the part and refreshes the serialized content" do
      docid = build_docid("NIST SP 800-53pt1")
      docid.remove_part!
      expect(docid.pubid.part).to be_nil
      expect(docid.content).to eq "NIST SP 800-53"
    end

    it "does not raise on an id without a part" do
      docid = build_docid("NIST IR 8259")
      expect { docid.remove_part! }.not_to raise_error
      expect(docid.content).to eq "NIST IR 8259"
    end
  end

  describe "#remove_date!" do
    it "removes a bare-year edition from the rendered string" do
      docid = build_docid("FIPS 46e1977")
      docid.remove_date!
      expect(docid.content).to eq "FIPS 46"
    end

    it "removes the trailing year but keeps the edition number" do
      docid = build_docid("NBS CIRC 11e2.1915")
      docid.remove_date!
      expect(docid.content).to eq "NBS CIRC 11e2"
    end

    it "does not change an id without a date/year" do
      docid = build_docid("NIST SP 800-53r5")
      docid.remove_date!
      expect(docid.content).to eq "NIST SP 800-53r5"
    end
  end

  describe "#remove_stage!" do
    it "drops a draft stage suffix" do
      docid = build_docid("NIST SP 800-37r2 ipd")
      docid.remove_stage!
      expect(docid.content).to eq "NIST SP 800-37r2"
    end

    it "does not change an id without a stage" do
      docid = build_docid("NIST SP 800-53r5")
      docid.remove_stage!
      expect(docid.content).to eq "NIST SP 800-53r5"
    end
  end

  describe "#to_all_parts!" do
    it "drops the part and marks the pubid all_parts without raising" do
      docid = build_docid("NIST SP 800-53pt1")
      expect { docid.to_all_parts! }.not_to raise_error
      expect(docid.pubid.part).to be_nil
      expect(docid.pubid.all_parts).to be true
      expect(docid.content).to eq "NIST SP 800-53"
    end

    it "also drops the stage on a staged id" do
      docid = build_docid("NIST SP 800-37r2 ipd")
      docid.to_all_parts!
      expect(docid.content).to eq "NIST SP 800-37r2"
    end
  end

  context "with an unparseable identifier" do
    subject(:docid) { build_docid("not a nist id") }

    it "falls back to the raw string without raising" do
      expect { docid }.not_to raise_error
      expect(docid.pubid).to be_nil
      expect(docid.content).to eq "not a nist id"
    end
  end

  context "with a non-NIST type (DOI)" do
    # A DOI like "NIST.SP.800-162" is a valid NIST pubid in dotted MR form and
    # would be rewritten to "NIST SP 800-162" if parsed. Only type "NIST" docids
    # are pubid-backed, so DOI content is preserved verbatim.
    subject(:docid) { build_docid("NIST.SP.800-162", type: "DOI", primary: false) }

    it "keeps the raw DOI string and does not parse it" do
      expect(docid.pubid).to be_nil
      expect(docid.content).to eq "NIST.SP.800-162"
    end
  end

  context "round trip through the NIST item model" do
    it "deserializes a type NIST docid as a Nist::Docidentifier" do
      xml = File.read "fixtures/nist_sp_800_27r2.xml", encoding: "UTF-8"
      item = Relaton::Nist::Bibitem.from_xml xml
      docid = item.docidentifier.first
      expect(docid).to be_a(described_class)
      expect(docid.content).to eq "NIST SP 800-37r2 ipd"
      expect(docid).to respond_to(:remove_part!, :to_all_parts!, :remove_date!)
    end

    it "preserves a DOI docid's content on round trip" do
      xml = File.read "fixtures/issued_published_dates.xml", encoding: "UTF-8"
      item = Relaton::Nist::Bibitem.from_xml xml
      primary = item.docidentifier.find(&:primary)
      doi = item.docidentifier.find { |d| d.type == "DOI" }
      expect(primary.content).to eq "NIST SP 800-162/Upd2"
      expect(doi.content).to eq "NIST.SP.800-162"
      expect(item.to_xml).to include %(<docidentifier type="DOI">NIST.SP.800-162</docidentifier>)
    end

    # Regression: lutaml applies setters in attribute-declaration order, so on
    # from_yaml `content=` runs before `type` is set. Adopting the pubid must not
    # depend on `type`, or YAML-loaded ids lose pubid backing and the mutators
    # silently no-op.
    it "keeps the primary pubid-backed after a YAML round trip" do
      xml = File.read "fixtures/nist_sp_800_27r2.xml", encoding: "UTF-8"
      item = Relaton::Nist::Bibitem.from_xml xml
      reloaded = Relaton::Nist::Item.from_yaml Relaton::Nist::Item.to_yaml(item)
      docid = reloaded.docidentifier.first
      expect(docid.pubid).to be_a(::Pubid::Nist::Identifier)
      docid.remove_stage!
      expect(docid.content).to eq "NIST SP 800-37r2"
    end

    # Regression: the docidentifier collection is typed Nist::Docidentifier, so
    # every element (incl. the DOI built by the parsers) must be that class or
    # lutaml's YAML serializer raises IncorrectModelError on a parent instance.
    it "serializes a parser-built primary+DOI collection to YAML" do
      data = Relaton::Nist::ItemData.new(
        docidentifier: [
          Relaton::Nist::Docidentifier.new(content: "NIST SP 800-162/Upd2", type: "NIST", primary: true),
          Relaton::Nist::Docidentifier.new(content: "NIST.SP.800-162", type: "DOI"),
        ],
      )
      yaml = Relaton::Nist::Item.to_yaml(data)
      expect(yaml).to include "NIST SP 800-162/Upd2"
      expect(yaml).to include "NIST.SP.800-162"
    end

    # A relation's nested bibitem (Nist::ItemBase) also uses Nist::Docidentifier,
    # so cross-reference ids are pubid-backed too.
    it "deserializes a relation's docidentifier as a Nist::Docidentifier" do
      xml = File.read "fixtures/retired_draft.xml", encoding: "UTF-8"
      item = Relaton::Nist::Bibitem.from_xml xml
      rel_docid = item.relation.first.bibitem.docidentifier.first
      expect(rel_docid).to be_a(described_class)
      expect(rel_docid.content).to eq "NIST SP 800-80 ipd"
      expect(rel_docid.pubid).to be_a(::Pubid::Nist::Identifier)
    end
  end
end
