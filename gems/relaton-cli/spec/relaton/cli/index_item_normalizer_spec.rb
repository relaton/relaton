require "relaton/cli/index_item_normalizer"

RSpec.describe Relaton::Cli::IndexItemNormalizer do
  subject(:record) { described_class.normalize(doc, lang: "en", yaml_ref: "x.yaml") }

  context "with a typical bilingual document" do
    let(:doc) do
      {
        "id" => "CCRIMeeting212009",
        "type" => "proceedings",
        "title" => [
          { "language" => "en", "content" => "21st meeting of the CCRI" },
          { "language" => "fr", "content" => "21<sup>e</sup> réunion du CCRI" },
        ],
        "docidentifier" => [
          { "language" => "en", "content" => "CCRI 21st Meeting (2009)", "primary" => true },
          { "language" => "fr", "content" => "CCRI 21<sup>e</sup>", "primary" => true },
        ],
        "date" => [{ "type" => "published", "at" => "2009-06-19" }],
        "source" => [{ "language" => "en", "type" => "citation", "content" => "https://bipm.org/x" }],
        "ext" => { "doctype" => { "content" => "meeting-report" } },
      }
    end

    it "picks the primary English DocID, title, doctype, date, link" do
      expect(record).to eq(
        "id" => "CCRI 21st Meeting (2009)",
        "title" => "21st meeting of the CCRI",
        "doctype" => "meeting-report",
        "stage" => nil,
        "date" => "2009-06-19",
        "link" => "https://bipm.org/x",
        "yaml" => "x.yaml",
      )
    end
  end

  it "strips inline HTML from titles/ids" do
    doc = { "title" => [{ "language" => "en", "content" => "A <sup>2</sup>" }],
            "docidentifier" => [{ "content" => "ID <b>1</b>" }] }
    expect(described_class.normalize(doc)["title"]).to eq("A 2")
    expect(described_class.normalize(doc)["id"]).to eq("ID 1")
  end

  it "falls back to docnumber then id when no docidentifier" do
    expect(described_class.normalize({ "docnumber" => "DN 5" })["id"]).to eq("DN 5")
    expect(described_class.normalize({ "id" => "RAW9" })["id"]).to eq("RAW9")
  end

  it "handles a plain string date and truncates to 10 chars" do
    expect(described_class.normalize({ "date" => "2020-05-01T12:00" })["date"]).to eq("2020-05-01")
  end

  it "reads date[].on when there is no .at" do
    doc = { "date" => [{ "type" => "published", "on" => "1999" }] }
    expect(described_class.normalize(doc)["date"]).to eq("1999")
  end

  it "reads a hash-shaped ext.doctype and a status.stage" do
    doc = { "ext" => { "doctype" => { "content" => "brochure" } },
            "status" => { "stage" => { "content" => "published" } } }
    r = described_class.normalize(doc)
    expect(r["doctype"]).to eq("brochure")
    expect(r["stage"]).to eq("published")
  end

  it "falls back to another language when the preferred one is absent" do
    doc = { "title" => [{ "language" => "fr", "content" => "Titre" }] }
    expect(described_class.normalize(doc, lang: "en")["title"]).to eq("Titre")
  end
end
