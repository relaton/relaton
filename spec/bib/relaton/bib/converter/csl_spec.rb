# frozen_string_literal: true

require "yaml"

describe Relaton::Bib::Converter::Csl do
  subject(:items) do
    described_class.to_item <<~CSL
      [
        {
          "id": "ISO 8601-1:2019",
          "type": "standard",
          "title": "Date and time — Representations for information interchange",
          "author": [
            {"family": "X", "given": "Mr."},
            {"literal": "International Organization for Standardization"}
          ],
          "editor": [{"family": "Z", "given": "Mr."}],
          "publisher": "ISO",
          "issued": {"date-parts": [[2019, 2, 25]]},
          "accessed": {"date-parts": [[2026, 11]]},
          "abstract": "Date and time representations.",
          "edition": "1",
          "ISBN": "978-92-67-10629-1",
          "URL": "https://www.iso.org/standard/80925.html",
          "DOI": "10.3403/30341748",
          "language": "en-US",
          "keyword": ["time", "date formats"]
        },
        {
          "id": "mrx05",
          "type": "article-journal",
          "title": "Something Great",
          "author": [{"family": "X", "given": "Mr."}],
          "container-title": "Journal",
          "issued": {"date-parts": [[2005]]},
          "volume": "1",
          "page": "10-20"
        },
        {
          "id": "mrx06",
          "type": "chapter",
          "title": "A Chapter",
          "author": [{"literal": "Mr. Y"}],
          "container-title": "Book title"
        }
      ]
    CSL
  end

  it "parses CSL-JSON into ItemData keyed by id" do
    expect(items).to be_instance_of Hash
    expect(items.keys).to eq ["ISO 8601-1:2019", "mrx05", "mrx06"]
    expect(items["mrx05"]).to be_instance_of Relaton::Bib::ItemData
  end

  it "maps the standard entry's fields" do
    item = items["ISO 8601-1:2019"]
    expect(item.id).to eq "ISO 8601-1:2019"
    expect(item.type).to eq "standard"
    expect(item.title.first.content).to eq "Date and time — Representations for information interchange"
    expect(item.title.first.type).to eq "main"
    expect(item.edition.content).to eq "1"
    expect(item.abstract.first.content).to eq "Date and time representations."
  end

  it "maps dates from date-parts at year, month and day precision" do
    dates = items["ISO 8601-1:2019"].date
    expect(dates.find { |d| d.type == "published" }.at.to_s).to eq "2019-02-25"
    expect(dates.find { |d| d.type == "accessed" }.at.to_s).to eq "2026-11"
  end

  it "maps family/given, literal and publisher contributors" do
    contribs = items["ISO 8601-1:2019"].contributor

    author = contribs[0]
    expect(author.person.name.surname.content).to eq "X"
    expect(author.person.name.forename.map(&:content)).to eq ["Mr."]
    expect(author.role[0].type).to eq "author"

    literal = contribs[1]
    expect(literal.person.name.completename.content).to eq "International Organization for Standardization"

    editor = contribs[2]
    expect(editor.person.name.surname.content).to eq "Z"
    expect(editor.role[0].type).to eq "editor"

    pub = contribs[3]
    expect(pub.organization.name[0].content).to eq "ISO"
    expect(pub.role[0].type).to eq "publisher"
  end

  it "maps identifiers and links" do
    item = items["ISO 8601-1:2019"]
    expect(item.docidentifier.map(&:type)).to eq [nil, "isbn"]
    expect(item.docidentifier[0].content).to eq "ISO 8601-1:2019"
    expect(item.docidentifier[0].primary).to be_truthy
    source = item.source
    expect(source.find { |s| s.type == "src" }.content).to eq "https://www.iso.org/standard/80925.html"
    expect(source.find { |s| s.type == "doi" }.content).to eq "10.3403/30341748"
  end

  it "maps language and keywords" do
    item = items["ISO 8601-1:2019"]
    expect(item.language).to eq ["en"]
    expect(item.keyword.map { |k| k.vocab.content }).to eq ["time", "date formats"]
  end

  it "maps volume and page extents" do
    extent = items["mrx05"].extent.first.locality
    expect(extent.find { |l| l.type == "volume" }.reference_from).to eq "1"
    page = extent.find { |l| l.type == "page" }
    expect(page.reference_from).to eq "10"
    expect(page.reference_to).to eq "20"
  end

  it "maps container-title to a journal series for article types" do
    series = items["mrx05"].series.first
    expect(series.type).to eq "journal"
    expect(series.title.first.content).to eq "Journal"
  end

  it "maps container-title to a partOf relation for chapters" do
    relation = items["mrx06"].relation.first
    expect(relation.type).to eq "partOf"
    expect(relation.bibitem.title.first.content).to eq "Book title"
    expect(items["mrx06"].series).to be_empty
  end

  it "round-trips the export" do
    docid = Relaton::Bib::Docidentifier.new type: "ISO", content: "ISO 8601-1:2019", primary: true
    item = Relaton::Bib::ItemData.new docidentifier: [docid], type: "standard",
                                      title: [Relaton::Bib::Title.new(type: "main", content: "Date and time")]
    back = described_class.to_item(described_class.from_item(item))["ISO 8601-1:2019"]
    expect(back.id).to eq "ISO 8601-1:2019"
    expect(back.type).to eq "standard"
    expect(back.title.first.content).to eq "Date and time"
  end
end
