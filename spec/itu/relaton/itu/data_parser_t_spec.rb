require "relaton/itu/data_parser_t"

describe Relaton::Itu::DataParserT do
  # A row as returned by the mws/api/recommendations/searchRecs endpoint
  # (main_edition_flag=0 — one row per edition; recs and supplements share the
  # same schema, distinguished by "Suppl" in rec_name).
  let(:row) do
    {
      "idrec" => 5194,
      "rec_name" => "A.1 (10/2000)",
      "title" => "Work Methods for Study Groups of the ITU Telecommunication Standardization Sector (ITU-T)",
      "approval_date" => "2000-10-06",
      "dms_link" => "https://www.itu.int/rec/T-REC-A.1-200010-S",
      "status" => "Superseded",
    }
  end

  let(:supplement) do
    {
      "idrec" => 15252,
      "rec_name" => "A Suppl. 2 (12/2022)",
      "title" => "Guidelines on interoperability experiments and proof-of-concept events",
      "approval_date" => "2022-12-15",
      "dms_link" => "https://www.itu.int/rec/T-REC-A.Sup2-202212-I",
      "status" => "In force",
    }
  end

  it "parse" do
    bib = described_class.parse(row)
    expect(bib).to be_instance_of Relaton::Itu::ItemData
    expect(bib.docidentifier.first.content).to eq "ITU-T A.1 (10/2000)"
    expect(bib.title.first.content).to eq "Work Methods for Study Groups of the ITU Telecommunication Standardization Sector (ITU-T)"
    expect(bib.date.first.type).to eq "published"
    expect(bib.date.first.at.to_s).to eq "2000-10-06"
    expect(bib.language).to eq ["en"]
    expect(bib.script).to eq ["Latn"]
    expect(bib.source.first.content.to_s).to eq "https://www.itu.int/rec/T-REC-A.1-200010-S"
    expect(bib.type).to eq "standard"
    expect(bib.ext.doctype.content).to eq "recommendation"
    expect(bib.ext.flavor).to eq "itu"
  end

  it "parses a supplement row" do
    bib = described_class.parse(supplement)
    expect(bib.docidentifier.first.content).to eq "ITU-T A Suppl. 2 (12/2022)"
    expect(bib.ext.doctype.content).to eq "recommendation-supplement"
    expect(bib.date.first.at.to_s).to eq "2022-12-15"
  end

  context "enrichment via getRecHdrDetail (agent given)" do
    let(:agent) { instance_double Mechanize }
    let(:detail) do
      { "summary" => "Information technology – Cloud computing – Overview and vocabulary",
        "iso_number" => "ISO/IEC 17788:2014 (Common)",
        "status" => "Superseded" }.to_json
    end
    let(:wg_page) do
      page = double("rec.aspx page")
      allow(page).to receive(:at).and_return(double("wg", text: "Study Group 13"))
      page
    end

    let(:editions) do
      [{ "idrec" => 5194, "rec_name" => "A.1 (10/2000)", "title" => "Work methods", "Version" => "3" },
       { "idrec" => 5195, "rec_name" => "A.1 (11/1988)", "title" => "Work methods" }].to_json
    end
    let(:supplements) do
      [{ "rec_name" => "A Suppl. 2 (12/2022)", "title_text" => "Guidelines" }].to_json
    end

    before do
      allow(agent).to receive(:get).with(a_string_including("getRecHdrDetail"))
        .and_return(double("resp", body: detail))
      allow(agent).to receive(:get).with(a_string_including("getRecEditions"))
        .and_return(double("resp", body: editions))
      allow(agent).to receive(:get).with(a_string_including("getRecSupplements"))
        .and_return(double("resp", body: supplements))
      allow(agent).to receive(:get).with(a_string_including("rec.aspx")).and_return(wg_page)
    end

    it "adds ISO co-id, abstract, status and editorial-group + publisher contributors" do
      bib = described_class.parse(row, agent)
      expect(bib.docidentifier.map { |d| d.content }).to include("ITU-T A.1 (10/2000)", "ISO/IEC 17788")
      expect(bib.abstract.first.content.to_s).to include "Overview and vocabulary"
      expect(bib.status.stage.content).to eq "Withdrawal" # "Superseded" != "In force"
      eg = bib.contributor.find { |c| c.role.any? { |r| r.type == "author" } }
      expect(eg.organization.abbreviation.content).to eq "ITU-T"
      expect(eg.organization.subdivision.first.name.first.content).to eq "Study Group 13"
      pub = bib.contributor.find { |c| c.role.any? { |r| r.type == "publisher" } }
      expect(pub.organization.abbreviation.content).to eq "ITU"
      expect(bib.date.first.at.to_s).to eq "2000-10-06" # day-precision, unchanged by enrichment
    end

    it "adds the edition and the other editions/supplements as relations" do
      bib = described_class.parse(row, agent)
      expect(bib.edition.content).to eq "3"
      types = bib.relation.map(&:type)
      expect(types).to eq %w[hasEdition complementOf]
      # the record's own edition is not related to itself
      expect(bib.relation.first.bibitem.docidentifier.first.content).to eq "A.1 (11/1988)"
      expect(bib.relation.last.bibitem.docidentifier.first.content).to eq "A Suppl. 2 (12/2022)"
    end

    it "degrades to the thin record when the detail fetch fails" do
      allow(agent).to receive(:get).and_raise(SocketError)
      bib = described_class.parse(row, agent)
      expect(bib.docidentifier.map { |d| d.content }).to eq ["ITU-T A.1 (10/2000)"]
      expect(bib.abstract).to eq []
      expect(bib.contributor).to eq []
      expect(bib.relation).to eq []
      expect(bib.edition).to be_nil
    end
  end

  context "fields that need no detail fetch" do
    it "sets the publisher's place and the copyright from the record's year" do
      bib = described_class.parse(row)
      expect(bib.place.first.city).to eq "Geneva"
      expect(bib.copyright.first.from).to eq "2000"
      expect(bib.copyright.first.owner.first.organization.abbreviation.content).to eq "ITU"
    end

    it "omits the copyright when the row has no date" do
      row["rec_name"] = "A.1"
      row.delete("approval_date")
      expect(described_class.parse(row).copyright).to eq []
    end
  end

  context "fetch_docid" do
    it "prefixes rec_name with ITU-T and keeps the edition date" do
      docid = described_class.fetch_docid(row)
      expect(docid).to be_instance_of Array
      expect(docid.size).to eq 1
      expect(docid.first).to be_instance_of Relaton::Itu::Docidentifier
      expect(docid.first.type).to eq "ITU"
      expect(docid.first.content).to eq "ITU-T A.1 (10/2000)"
      expect(docid.first.primary).to be true
    end

    it "returns empty array when rec_name is missing" do
      row.delete("rec_name")
      expect(described_class.fetch_docid(row)).to eq []
    end

    # searchRecs serves a handful of rec_names with a doubled space or a
    # `Suppl.` run together with its number. `Pubid::Itu` rejects both spellings,
    # so those records were written but left out of the index; the canonical
    # spelling parses. Measured against the published dataset: 15 records.
    {
      "a doubled space" => ["D.271  (10/2016)", "ITU-T D.271 (10/2016)"],
      "Suppl. run into its number" => ["D.211 Suppl.1 (05/2010)", "ITU-T D.211 Suppl. 1 (05/2010)"],
      "a series supplement" => ["E Suppl.1 (10/1976)", "ITU-T E Suppl. 1 (10/1976)"],
      # pubid parses "(V10)" but not the bare "v10" ITU also emits.
      "a bare lowercase version" => ["H.222.0 v10 (04/2025)", "ITU-T H.222.0 (V10) (04/2025)"],
      "a bare uppercase version" => ["H.764 V2 (11/2019)", "ITU-T H.764 (V2) (11/2019)"],
      "a version on an amended edition" => ["H.222.0 v8 (2021) Amd. 1 (12/2022)",
                                           "ITU-T H.222.0 (V8) (2021) Amd. 1 (12/2022)"],
      "a space where the series dot belongs" => ["G 231 (10/1976)", "ITU-T G.231 (10/1976)"],
    }.each do |what, (rec_name, expected)|
      it "normalizes #{what} so the id can be indexed" do
        expect(described_class.fetch_docid(row.merge("rec_name" => rec_name)).first.content).to eq expected
      end
    end

    it "leaves a well-formed rec_name byte-identical" do
      # The other ~16k records must serialize exactly as before — including the
      # canonical "(V14)" spelling and forms pubid cannot parse at all, which are
      # deliberately not guessed at.
      ["A.1 (10/2000)", "G.711 (11/1988)", "H.264 (V14) (08/2021)", "A Suppl. 2 (12/2022)",
       "D.200 R (10/1976)", "E.250 bis (12/1972)", "G.101 App. I (05/2000)",
       "E-100 series Suppl. 1 (02/2019)", "D.301 R/F.66 (12/1972)"].each do |name|
        expect(described_class.fetch_docid(row.merge("rec_name" => name)).first.content).to eq "ITU-T #{name}"
      end
    end
  end

  context "fetch_date" do
    it "prefers the day-precision approval_date" do
      date = described_class.fetch_date(row)
      expect(date.first).to be_instance_of Relaton::Bib::Date
      expect(date.first.type).to eq "published"
      expect(date.first.at.to_s).to eq "2000-10-06"
    end

    it "falls back to the (MM/YYYY) rec_name date when approval_date is absent" do
      row.delete("approval_date")
      expect(described_class.fetch_date(row).first.at.to_s).to eq "2000-10"
    end

    it "returns empty array when there is no date at all" do
      row["rec_name"] = "A.1"
      row.delete("approval_date")
      expect(described_class.fetch_date(row)).to eq []
    end
  end

  context "fetch_source" do
    it "uses dms_link as the source URI" do
      source = described_class.fetch_source(row)
      expect(source.first).to be_instance_of Relaton::Bib::Uri
      expect(source.first.content.to_s).to eq "https://www.itu.int/rec/T-REC-A.1-200010-S"
    end

    it "returns empty array when dms_link is missing or a placeholder" do
      row["dms_link"] = "-"
      expect(described_class.fetch_source(row)).to eq []
    end
  end

  context "fetch_doctype" do
    it "maps a recommendation" do
      expect(described_class.fetch_doctype(row).content).to eq "recommendation"
    end

    it "maps a supplement" do
      expect(described_class.fetch_doctype(supplement).content).to eq "recommendation-supplement"
    end

    it "maps an amendment" do
      row["rec_name"] = "A.2 (2004) Amd. 1 (07/2006)"
      expect(described_class.fetch_doctype(row).content).to eq "recommendation-amendment"
    end

    it "maps a corrigendum" do
      row["rec_name"] = "G.711 (1988) Cor. 1 (09/2009)"
      expect(described_class.fetch_doctype(row).content).to eq "recommendation-corrigendum"
    end

    it "maps an annex" do
      row["rec_name"] = "A.23 Annex A (06/2014)"
      expect(described_class.fetch_doctype(row).content).to eq "recommendation-annex"
    end
  end
end
