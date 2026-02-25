require "relaton/itu/data_parser_r"

describe Relaton::Itu::DataParserR do
  let(:result) do
    {
      "Title" => "ITU-R M.2150-2 (12/2023): Detailed specifications of the terrestrial radio interfaces",
      "Properties" => [
        { "Title" => "Publication date", "Value" => "January, 2024" },
        { "Title" => "Type", "Value" => "ITU-R Recommendations" },
      ],
      "Locations" => [
        { "Type" => "pdf", "RawHref" => "https://www.itu.int/rec/R-REC-M.2150-2.pdf" },
      ],
    }
  end

  it "parse" do
    bib = described_class.parse(result)
    expect(bib).to be_instance_of Relaton::Itu::ItemData
    expect(bib.docidentifier.first.content).to eq "ITU-R M.2150-2"
    expect(bib.title.first.content).to eq "Detailed specifications of the terrestrial radio interfaces"
    expect(bib.date.first.type).to eq "published"
    expect(bib.date.first.at.to_s).to eq "2024-01"
    expect(bib.language).to eq ["en"]
    expect(bib.script).to eq ["Latn"]
    expect(bib.source.first.content.to_s).to eq "https://www.itu.int/rec/R-REC-M.2150-2.pdf"
    expect(bib.type).to eq "standard"
    expect(bib.ext.doctype.content).to eq "recommendation"
    expect(bib.ext.flavor).to eq "itu"
  end

  it "parse returns nil for unknown type" do
    result["Properties"] = [{ "Title" => "Type", "Value" => "ITU-R Opinions" }]
    expect(described_class.parse(result)).to be_nil
  end

  context "fetch_docid" do
    it "extracts ID from title" do
      docid = described_class.fetch_docid(result)
      expect(docid).to be_instance_of Array
      expect(docid.size).to eq 1
      expect(docid.first).to be_instance_of Relaton::Itu::Docidentifier
      expect(docid.first.type).to eq "ITU"
      expect(docid.first.content).to eq "ITU-R M.2150-2"
      expect(docid.first.primary).to be true
    end

    it "returns empty array when title has no ID" do
      result["Title"] = "No ID here"
      expect(described_class.fetch_docid(result)).to eq []
    end
  end

  context "fetch_title" do
    it "extracts title after colon" do
      title = described_class.fetch_title(result)
      expect(title).to be_instance_of Array
      expect(title.size).to eq 1
      expect(title.first).to be_instance_of Relaton::Bib::Title
      expect(title.first.type).to eq "main"
      expect(title.first.content).to eq "Detailed specifications of the terrestrial radio interfaces"
      expect(title.first.language).to eq "en"
      expect(title.first.script).to eq "Latn"
    end

    it "uses full title when no colon" do
      result["Title"] = "ITU-R M.2150-2"
      title = described_class.fetch_title(result)
      expect(title.first.content).to eq "ITU-R M.2150-2"
    end
  end

  context "fetch_date" do
    it "parses month-year format" do
      date = described_class.fetch_date(result)
      expect(date).to be_instance_of Array
      expect(date.size).to eq 1
      expect(date.first).to be_instance_of Relaton::Bib::Date
      expect(date.first.type).to eq "published"
      expect(date.first.at.to_s).to eq "2024-01"
    end

    it "parses year-only format" do
      result["Properties"] = [
        { "Title" => "Publication date", "Value" => "2023" },
        { "Title" => "Type", "Value" => "ITU-R Recommendations" },
      ]
      date = described_class.fetch_date(result)
      expect(date.first.at.to_s).to eq "2023"
    end

    it "returns empty array when no publication date" do
      result["Properties"] = [{ "Title" => "Type", "Value" => "ITU-R Recommendations" }]
      expect(described_class.fetch_date(result)).to eq []
    end
  end

  context "fetch_source" do
    it "extracts PDF URL" do
      source = described_class.fetch_source(result)
      expect(source).to be_instance_of Array
      expect(source.size).to eq 1
      expect(source.first).to be_instance_of Relaton::Bib::Uri
      expect(source.first.type).to eq "pdf"
      expect(source.first.content.to_s).to eq "https://www.itu.int/rec/R-REC-M.2150-2.pdf"
    end

    it "returns empty array when no locations" do
      result.delete("Locations")
      expect(described_class.fetch_source(result)).to eq []
    end

    it "returns empty array when no PDF location" do
      result["Locations"] = [{ "Type" => "html", "RawHref" => "https://example.com" }]
      expect(described_class.fetch_source(result)).to eq []
    end
  end

  context "fetch_doctype" do
    it "maps ITU-R Recommendations" do
      doctype = described_class.fetch_doctype(result)
      expect(doctype).to be_instance_of Relaton::Itu::Doctype
      expect(doctype.content).to eq "recommendation"
    end

    it "maps ITU-R Questions" do
      result["Properties"] = [{ "Title" => "Type", "Value" => "ITU-R Questions" }]
      expect(described_class.fetch_doctype(result).content).to eq "question"
    end

    it "maps ITU-R Reports" do
      result["Properties"] = [{ "Title" => "Type", "Value" => "ITU-R Reports" }]
      expect(described_class.fetch_doctype(result).content).to eq "technical-report"
    end

    it "maps Handbooks" do
      result["Properties"] = [{ "Title" => "Type", "Value" => "Handbooks" }]
      expect(described_class.fetch_doctype(result).content).to eq "handbook"
    end

    it "maps ITU-R Resolutions" do
      result["Properties"] = [{ "Title" => "Type", "Value" => "ITU-R Resolutions" }]
      expect(described_class.fetch_doctype(result).content).to eq "resolution"
    end

    it "returns nil for unknown type" do
      result["Properties"] = [{ "Title" => "Type", "Value" => "ITU-R Opinions" }]
      expect(described_class.fetch_doctype(result)).to be_nil
    end

    it "returns nil when no properties" do
      result.delete("Properties")
      expect(described_class.fetch_doctype(result)).to be_nil
    end
  end
end
