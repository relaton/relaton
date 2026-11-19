describe Relaton::Eu::Parser, :no_index_fixture do
  # Every row is a real CELLAR answer of `Cellar::QUERY` (fixtures/cellar/).
  def row(celex)
    Dir[File.join(CellarStub::FIXTURES, "*.json")].each do |file|
      data = JSON.parse File.read(file, encoding: "UTF-8")
      found = data.dig("results", "bindings").find { |b| b.dig("celex", "value") == celex }
      return found if found
    end
    raise "no fixture row #{celex}"
  end

  def parse(celex) = described_class.parse(row(celex))

  def docid(item, type) = item.docidentifier.find { |d| d.type == type }&.content

  context "the act identifier" do
    it "is the primary docidentifier, in the order the Official Journal prints" do
      item = parse "32011R1227"
      primary = item.docidentifier.find(&:primary)
      expect(primary.type).to eq "EU"
      expect(primary.content).to eq "EU Regulation 1227/2011"
    end

    it "puts the year first from 2015" do
      expect(docid(parse("32016R0679"), "EU")).to eq "EU Regulation 2016/679"
    end

    it "reads a directive" do
      expect(docid(parse("32016L0680"), "EU")).to eq "EU Directive 2016/680"
    end

    it "reads a directive whose title gives a two-digit year" do
      expect(docid(parse("31993L0042"), "EU")).to eq "EU Directive 1993/42"
    end

    # Before 2015 a decision can print either order; `No` marks
    # <number>/<year>, and only the title says which one an act used.
    it "keeps the number-first order of a pre-2015 decision from its title" do
      expect(docid(parse("32013D1082"), "EU")).to eq "EU Decision 1082/2013"
    end

    # The CELEX number is CELLAR's sequence, not the act number: ECB
    # decision 2016/245 is CELEX 32016D0002.
    it "comes from the ELI, not from the CELEX number" do
      item = parse "32016D0002"
      expect(docid(item, "EU")).to eq "EU Decision 2016/245"
      expect(docid(item, "CELEX")).to eq "CELEX 32016D0002"
    end

    it "reads an implementing regulation as a regulation" do
      item = parse "32016R1356"
      expect(docid(item, "EU")).to eq "EU Regulation 2016/1356"
      expect(docid(item, "ELI")).to eq "http://data.europa.eu/eli/reg_impl/2016/1356/oj"
    end

    it "is a pubid the index can key" do
      pubid = described_class.new(row("32011R1227")).pubid
      expect(pubid).to be_a Pubid::Eu::Identifiers::Regulation
      expect(pubid.to_s).to eq "EU Regulation 1227/2011"
    end
  end

  context "a work the flavor does not cover" do
    it "skips a corrigendum" do
      expect(parse("32016D0002R(01)")).to be_nil
    end

    it "skips a work with no ELI" do
      expect(parse("32011D0812(01)")).to be_nil
    end
  end

  context "the bibliographic item" do
    subject(:item) { parse "32011R1227" }

    it "has the CELEX and the ELI beside the act identifier" do
      expect(item.docidentifier.map { |d| [d.type, d.content, d.primary] }).to eq [
        ["EU", "EU Regulation 1227/2011", true],
        ["CELEX", "CELEX 32011R1227", nil],
        ["ELI", "http://data.europa.eu/eli/reg/2011/1227/oj", nil],
      ]
    end

    it "has the English title without the EEA relevance note" do
      title = item.title.first
      expect(title.language).to eq "en"
      expect(title.content).to eq "Regulation (EU) No 1227/2011 of the European " \
                                  "Parliament and of the Council of 25 October 2011 " \
                                  "on wholesale energy market integrity and transparency"
    end

    # `EEA_NOTE` matches one space only: it relies on `#initialize`
    # collapsing each whitespace run in the title.
    ["  (Text with EEA relevance)", " ( Text with EEA relevance )  .",
     "\n\tText with EEA relevance"].each do |note|
      it "drops the EEA relevance note after whitespace #{note.inspect}" do
        raw = row("32011R1227").merge(
          "title" => { "value" => "Regulation (EU) No 1227/2011 on energy#{note}" },
        )
        title = described_class.parse(raw).title.first.content
        expect(title).to eq "Regulation (EU) No 1227/2011 on energy"
      end
    end

    it "has the date of the document and the entry into force" do
      expect(item.date.map { |d| [d.type, d.at.to_s] }).to eq [
        %w[issued 2011-10-25], %w[implemented 2011-12-28]
      ]
    end

    it "takes the first entry into force of an act that has two" do
      dates = parse("32016R0679").date.map { |d| [d.type, d.at.to_s] }
      expect(dates).to include %w[implemented 2016-05-24]
    end

    it "has the authors and the Publications Office as publisher" do
      contribs = item.contributor.map do |c|
        [c.role.first.type, c.organization.name.first.content,
         c.organization.abbreviation&.content]
      end
      expect(contribs).to eq [
        ["author", "Council of the European Union", "CONSIL"],
        ["author", "European Parliament", "EP"],
        ["publisher", "Publications Office of the European Union", "OP"],
      ]
    end

    # `COALESCE` in the query gives such an author `<uri>|`.
    it "names an author with no English label by its code" do
      bare = row("32011R1227").merge(
        "authors" => { "value" => "http://publications.europa.eu/resource/authority/corporate-body/XYZ|" },
      )
      org = described_class.parse(bare).contributor.first.organization
      expect([org.name.first.content, org.abbreviation.content]).to eq %w[XYZ XYZ]
    end

    it "has the in-force status" do
      expect(item.status.stage.content).to eq "in-force"
      expect(parse("32013D1082").status.stage.content).to eq "not-in-force"
    end

    it "has the EUR-Lex page as its source" do
      expect(item.source.map { |s| [s.type, s.content.to_s] }).to eq [
        ["src", "https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32011R1227"],
      ]
    end

    it "relates the acts it repeals and amends by CELEX" do
      rels = parse("32013D1082").relation.map do |r|
        [r.type, r.bibitem.docidentifier.first.content]
      end
      expect(rels).to eq [
        ["obsoletes", "CELEX 31998D2119"], ["obsoletes", "CELEX 32003D0534"],
        ["updates", "CELEX 32003R1882"], ["updates", "CELEX 32007D0875"],
        ["updates", "CELEX 32009R0596"],
      ]
    end

    it "is a document of the eu flavor, with the act as doctype" do
      expect(item.type).to eq "standard"
      expect(item.ext.doctype.content).to eq "regulation"
      expect(item.ext.flavor).to eq "eu"
      expect(parse("32016L0680").ext.doctype.content).to eq "directive"
    end

    it "carries no fetch date: the data file must not change every day" do
      expect(item.fetched).to be_nil
    end

    it "writes bibdata XML that the generic grammar accepts" do
      Dir.mktmpdir do |dir|
        file = File.join dir, "bibdata.xml"
        File.write file, item.to_xml(bibdata: true), encoding: "UTF-8"
        expect(Relaxng.new("../../grammar/biblio-compile.rng").validate(file)).to eq []
      end
    end

    it "writes bibitem XML that the generic grammar accepts" do
      Dir.mktmpdir do |dir|
        file = File.join dir, "bibitem.xml"
        File.write file, item.to_xml, encoding: "UTF-8"
        expect(Relaxng.new("../../grammar/biblio-compile.rng").validate(file)).to eq []
      end
    end
  end
end
