require "relaton/itu/data_parser_r"

describe Relaton::Itu::DataParserR do
  # A normalized row as DataCrawlerR emits it — the RunSearch result hash this
  # module used to take no longer has a producer (issue #75).
  let(:row) do
    {
      id: "R-REC-BO.1130-5-202602-I",
      code: "BO.1130-5 (02/2026)",
      title: "Systems for digital satellite broadcasting to vehicular, portable and fixed receivers",
      status: "In force (Main)",
      date: "2026-02-18",
      family: "R-REC",
      url: "https://www.itu.int/rec/R-REC-BO.1130-5-202602-I/en",
      pdf: "https://www.itu.int/dms_pubrec/itu-r/rec/bo/R-REC-BO.1130-5-202602-I!!PDF-E.pdf",
    }
  end

  it "parse" do
    bib = described_class.parse(row)
    expect(bib).to be_instance_of Relaton::Itu::ItemData
    expect(bib.docidentifier.first.content).to eq "ITU-R BO.1130-5"
    expect(bib.title.first.content).to eq row[:title]
    expect(bib.date.first.type).to eq "published"
    expect(bib.date.first.at.to_s).to eq "2026-02-18"
    expect(bib.language).to eq ["en"]
    expect(bib.script).to eq ["Latn"]
    expect(bib.source.first.content.to_s).to eq row[:pdf]
    expect(bib.type).to eq "standard"
    expect(bib.ext.doctype.content).to eq "recommendation"
    expect(bib.ext.flavor).to eq "itu"
  end

  it "parse returns nil for an unknown family" do
    expect(described_class.parse(row.merge(family: "R-OPINION"))).to be_nil
  end

  it "does not model the scraped status" do
    # No published ITU-R record carries a status, so emitting one would make
    # every re-harvested record diff against the preserved dataset.
    expect(described_class.parse(row).to_yaml).not_to include "In force"
  end

  it "drops a record with no docid rather than emitting an unwritable one" do
    # DataFetcher#write_file reads `docidentifier.find(&:primary).content`.
    expect(described_class.parse(row.merge(code: ""))).to be_nil
  end

  it "folds the non-breaking space ITU pads the code with" do
    docid = described_class.fetch_docid(row.merge(code: "BO.1130-5 (02/2026) "))
    expect(docid.first.content).to eq "ITU-R BO.1130-5"
  end

  context "fetch_docid" do
    it "takes the displayed code, not the page id" do
      docid = described_class.fetch_docid(row)
      expect(docid.size).to eq 1
      expect(docid.first).to be_instance_of Relaton::Itu::Docidentifier
      expect(docid.first.type).to eq "ITU"
      expect(docid.first.content).to eq "ITU-R BO.1130-5"
      expect(docid.first.primary).to be true
    end

    it "keeps an edition-less code edition-less" do
      # R-REC-BO.1212-0-199510-I would give "ITU-R BO.1212-0"; the published
      # record is "ITU-R BO.1212" (data/itu-r-bo-1212.yaml).
      docid = described_class.fetch_docid(row.merge(id: "R-REC-BO.1212-0-199510-I", code: "BO.1212 (10/95)"))
      expect(docid.first.content).to eq "ITU-R BO.1212"
    end

    it "returns an empty array and flags the error for a blank code" do
      errors = Hash.new true
      expect(described_class.fetch_docid(row.merge(code: ""), errors)).to eq []
      expect(errors[:docid]).to be true
    end
  end

  context "fetch_title" do
    it "extracts the title" do
      title = described_class.fetch_title(row)
      expect(title.size).to eq 1
      expect(title.first).to be_instance_of Relaton::Bib::Title
      expect(title.first.type).to eq "main"
      expect(title.first.content).to eq row[:title]
      expect(title.first.language).to eq "en"
      expect(title.first.script).to eq "Latn"
    end

    it "returns an empty array for a blank title" do
      expect(described_class.fetch_title(row.merge(title: " "))).to eq []
    end
  end

  context "fetch_date" do
    it "keeps the day-precision approval date" do
      date = described_class.fetch_date(row)
      expect(date.size).to eq 1
      expect(date.first).to be_instance_of Relaton::Bib::Date
      expect(date.first.type).to eq "published"
      expect(date.first.at.to_s).to eq "2026-02-18"
    end

    it "accepts a month-precision date" do
      expect(described_class.fetch_date(row.merge(date: "2000-07")).first.at.to_s).to eq "2000-07"
    end

    it "returns an empty array when there is no date" do
      expect(described_class.fetch_date(row.merge(date: nil))).to eq []
    end
  end

  context "fetch_source" do
    it "extracts the PDF URL" do
      source = described_class.fetch_source(row)
      expect(source.size).to eq 1
      expect(source.first).to be_instance_of Relaton::Bib::Uri
      expect(source.first.type).to eq "pdf"
      expect(source.first.content.to_s).to eq row[:pdf]
    end

    it "returns an empty array when there is no PDF" do
      expect(described_class.fetch_source(row.merge(pdf: nil))).to eq []
    end
  end

  context "fetch_doctype" do
    {
      "R-REC" => "recommendation", "R-REP" => "technical-report", "R-QUE" => "question",
      "R-RES" => "resolution", "R-HDB" => "handbook"
    }.each do |family, doctype|
      it "maps #{family}" do
        expect(described_class.fetch_doctype(row.merge(family: family))).to be_instance_of Relaton::Itu::Doctype
        expect(described_class.fetch_doctype(row.merge(family: family)).content).to eq doctype
      end
    end

    it "returns nil and flags the error for an unknown family" do
      errors = Hash.new true
      expect(described_class.fetch_doctype(row.merge(family: "R-OPINION"), errors)).to be_nil
      expect(errors[:doctype]).to be true
    end

    it "returns nil when the family is missing" do
      expect(described_class.fetch_doctype(row.reject { |k, _| k == :family })).to be_nil
    end
  end
end
