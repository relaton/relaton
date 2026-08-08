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
      expect(record.slice("id", "title", "doctype", "stage", "date", "link", "yaml")).to eq(
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

  describe "detail fields for the per-document page" do
    let(:doc) do
      {
        "docidentifier" => [
          { "language" => "en", "content" => "ISO 1234:2020", "type" => "ISO", "primary" => true },
          { "content" => "10.1000/xyz", "type" => "DOI" },
        ],
        "title" => [{ "language" => "en", "content" => "A title" }],
        "abstract" => [
          { "language" => "en", "content" => "An <p>English</p> abstract." },
          { "language" => "fr", "content" => "Un résumé." },
        ],
        "edition" => { "content" => "2" },
        "language" => %w[en fr],
        "keyword" => ["metrology", { "content" => "units" }],
        "date" => [
          { "type" => "published", "at" => "2020-05-01" },
          { "type" => "created", "on" => "2019" },
        ],
        "contributor" => [
          { "role" => [{ "type" => "publisher" }],
            "organization" => { "name" => [
              { "language" => "en", "content" => "International Organization for Standardization" },
              { "language" => "fr", "content" => "Organisation internationale de normalisation" },
            ] } },
          { "role" => [{ "type" => "author" }],
            "person" => { "name" => { "completename" => { "content" => "Ada Lovelace" } } } },
        ],
      }
    end

    it "extracts a preferred-language, HTML-stripped abstract" do
      expect(record["abstract"]).to eq("An English abstract.")
    end

    it "extracts the edition, languages and keywords" do
      expect(record["edition"]).to eq("2")
      expect(record["languages"]).to eq(%w[en fr])
      expect(record["keywords"]).to eq(%w[metrology units])
    end

    it "extracts all identifiers with their type" do
      expect(record["docids"]).to include(
        a_hash_including("id" => "ISO 1234:2020", "type" => "ISO"),
        a_hash_including("id" => "10.1000/xyz", "type" => "DOI"),
      )
    end

    it "extracts all dates with their type and value" do
      expect(record["dates"]).to eq(
        [{ "type" => "published", "value" => "2020-05-01" },
         { "type" => "created", "value" => "2019" }],
      )
    end

    it "extracts contributors (org + person names) with roles" do
      expect(record["contributors"]).to eq(
        [{ "name" => "International Organization for Standardization", "role" => "publisher" },
         { "name" => "Ada Lovelace", "role" => "author" }],
      )
    end

    it "derives the publisher from the publisher-role contributor" do
      expect(record["publisher"]).to eq("International Organization for Standardization")
    end

    it "omits empty detail fields on a minimal document" do
      minimal = described_class.normalize({ "id" => "RAW9" })
      expect(minimal.keys).to contain_exactly(
        "id", "title", "doctype", "stage", "date", "link", "yaml",
      )
    end

    it "handles single unwrapped Hash entries without Array() explosion" do
      doc = {
        "contributor" => { "role" => { "type" => "author" },
                            "organization" => { "name" => { "content" => "Solo Org" } } },
        "date" => { "type" => "published", "at" => "2021-01-01" },
      }
      r = described_class.normalize(doc)
      expect(r["contributors"]).to eq([{ "name" => "Solo Org", "role" => "author" }])
      expect(r["dates"]).to eq([{ "type" => "published", "value" => "2021-01-01" }])
    end
  end
end
