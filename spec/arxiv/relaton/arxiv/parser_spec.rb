describe Relaton::Arxiv::Parser do
  def entry(file)
    described_class.parse File.read("fixtures/#{file}", encoding: "UTF-8")
  end

  context "an old-style id with a journal reference" do
    subject(:item) { entry "hep-th-9901001.xml" }

    it "is an article" do
      expect(item).to be_instance_of Relaton::Bib::ItemData
      expect(item.type).to eq "article"
    end

    it "has the versioned arXiv id as the primary docidentifier" do
      primary = item.docidentifier.first
      expect(primary.type).to eq "arXiv"
      expect(primary.content).to eq "arXiv:hep-th/9901001v3"
      expect(primary.primary).to be true
    end

    it "has arXiv's DataCite DOI without the version" do
      doi = item.docidentifier.detect { |d| d.type == "DOI" }
      expect(doi.content).to eq "10.48550/arXiv.hep-th/9901001"
      expect(doi.primary).to be_falsey
    end

    it "has the title, the abstract and the version" do
      expect(item.title.first.content).to eq "String Junctions and Their Duals in Heterotic String Theory"
      expect(item.title.first.type).to eq "main"
      expect(item.abstract.first.content).to start_with "We explicitly give"
      expect(item.version.first.content).to eq "3"
    end

    it "has the published and the updated dates" do
      expect(item.date.map { |d| [d.type, d.at.to_s] }).to eq [
        %w[published 1999-01-01], %w[updated 1999-05-10]
      ]
    end

    it "has the authors" do
      author = item.contributor.first
      expect(author.role.first.type).to eq "author"
      expect(author.person.name.completename.content).to eq "Yosuke Imamura"
    end

    it "has the categories as keywords, the primary first" do
      expect(item.keyword.map { |k| k.vocab.first.content }).to eq ["hep-th"]
    end

    it "has the abstract page and the PDF" do
      expect(item.source.map { |s| [s.type, s.content.to_s] }).to eq [
        ["src", "https://arxiv.org/abs/hep-th/9901001v3"],
        ["pdf", "https://arxiv.org/pdf/hep-th/9901001v3"],
      ]
    end

    it "relates the journal article by its DOI" do
      rel = item.relation.first
      expect(rel.type).to eq "hasManifestation"
      expect(rel.bibitem.docidentifier.first.type).to eq "DOI"
      expect(rel.bibitem.docidentifier.first.content).to eq "10.1143/PTP.101.1155"
    end

    it "keeps the journal reference as a note" do
      note = item.note.detect { |n| n.type == "journal-ref" }
      expect(note.content).to eq "Prog.Theor.Phys.101:1155-1164,1999"
    end

    it "is of the arxiv flavor" do
      expect(item.ext.flavor).to eq "arxiv"
    end

    it "round-trips through XML and YAML" do
      xml = Relaton::Bib::Bibitem.to_xml(item)
      expect(Relaton::Bib::Bibitem.from_xml(xml).docidentifier.first.content)
        .to eq "arXiv:hep-th/9901001v3"
      yaml = Relaton::Bib::Item.to_yaml(item)
      expect(Relaton::Bib::Item.from_yaml(yaml).title.first.content)
        .to eq item.title.first.content
    end
  end

  context "a new-style id with no journal reference" do
    subject(:item) { entry "1706.03762.xml" }

    it "is a preprint (misc)" do
      expect(item.type).to eq "misc"
      expect(item.relation).to be_empty
    end

    it "has the docidentifiers" do
      expect(item.docidentifier.map(&:content)).to eq [
        "arXiv:1706.03762v7", "10.48550/arXiv.1706.03762"
      ]
    end

    it "has every author and the categories in order" do
      expect(item.contributor.size).to eq 8
      expect(item.contributor.first.person.name.completename.content).to eq "Ashish Vaswani"
      expect(item.keyword.map { |k| k.vocab.first.content }).to eq %w[cs.CL cs.LG]
    end
  end

  it "answers nil for a feed with no entry" do
    expect(entry("not-found.xml")).to be_nil
  end

  it "answers nil for arXiv's error entry" do
    expect(entry("error-entry.xml")).to be_nil
  end

  context "a minimal entry" do
    let(:xml) do
      <<~XML
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry><id>http://arxiv.org/abs/math.GT/0309136v2</id></entry>
        </feed>
      XML
    end

    subject(:item) { described_class.parse xml }

    it "reads an old-style id with a subject class" do
      expect(item.docidentifier.map(&:content)).to eq [
        "arXiv:math.GT/0309136v2", "10.48550/arXiv.math.GT/0309136"
      ]
      expect(item.version.first.content).to eq "2"
    end

    it "leaves out the elements the entry does not have" do
      expect(item.title).to be_empty
      expect(item.abstract).to be_empty
      expect(item.date).to be_empty
      expect(item.contributor).to be_empty
      expect(item.type).to eq "misc"
    end
  end
end
