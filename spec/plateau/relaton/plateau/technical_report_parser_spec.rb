require "relaton/plateau/data_fetcher"

RSpec.describe Relaton::Plateau::TechnicalReportParser do
  let(:entry) do
    {
      "id" => "cG9zdDo4Mzcz",
      "date" => "2024-03-29T10:00:29",
      "slug" => "93",
      "technicalReport" => {
        "title" => "歴史・文化・営みを継承するメタバース体験の構築 技術検証レポート",
        "subtitle" => "歴史・文化・営みを継承するメタバース体験の構築の技術資料 (2023年度)",
        "thumbnail" => {
          "mediaItemUrl" => "/plateau/uploads/2024/03/plateau_tech_doc_0093_ver01.jpg",
          "mediaDetails" => { "width" => 1275, "height" => 1650 }
        },
        "pdf" => "https://www.mlit.go.jp/plateau/file/libraries/doc/plateau_tech_doc_0093_ver01.pdf",
        "filesize" => "22005029"
      },
      "technicalReportCategories" => { "nodes" => [{ "name" => "Use Case", "slug" => "usecase" }] },
      "usecaseFields" => {"nodes" => [{ "name" => "地域活性化・観光", "slug" => "regional-activation_sightseeing" }] },
      "globalTags" => {
        "nodes" => [
          { "name" => "Unreal Engine", "slug" => "unreal_engine" },
          { "name" => "デジタルツイン", "slug" => "digital-twin" },
          { "name" => "Unity", "slug" => "unity" },
          { "name" => "AR/VR", "slug" => "ar_vr" }
        ]
      }
    }
  end

  subject { described_class.new entry }

  context "parse" do
    let(:bibitem) { subject.parse }
    it { expect(bibitem).to be_instance_of Relaton::Plateau::ItemData }
    it { expect(bibitem.docidentifier[0]).to be_instance_of Relaton::Bib::Docidentifier }
    it { expect(bibitem.docnumber).to eq "Technical Report #93 1.0" }
    it { expect(bibitem.title[0]).to be_instance_of Relaton::Bib::Title }
    it { expect(bibitem.abstract[0]).to be_instance_of Relaton::Bib::Abstract }
    it { expect(bibitem.depiction[0]).to be_instance_of Relaton::Bib::Depiction }
    it { expect(bibitem.edition).to be_instance_of Relaton::Bib::Edition }
    it { expect(bibitem.type).to eq "standard" }
    it { expect(bibitem.ext).to be_instance_of Relaton::Plateau::Ext }
    it { expect(bibitem.ext.doctype).to be_instance_of Relaton::Plateau::Doctype }
    it { expect(bibitem.ext.subdoctype).to eq "Use Case" }
    it { expect(bibitem.date[0]).to be_instance_of Relaton::Bib::Date }
    it { expect(bibitem.source[0]).to be_instance_of Relaton::Bib::Uri }
    it { expect(bibitem.contributor[0]).to be_instance_of Relaton::Bib::Contributor }
    it { expect(bibitem.ext.filesize).to eq 22005029 }
    it { expect(bibitem.keyword[0]).to be_instance_of Relaton::Bib::Keyword }
    it { expect(bibitem.ext.structuredidentifier[0]).to be_instance_of Relaton::Bib::StructuredIdentifier }
  end

  it "creates technical report" do
    expect(subject.instance_variable_get(:@entry)).to be entry
    expect(subject.instance_variable_get(:@item)).to be entry["technicalReport"]
  end

  it "parse_docidentifier" do
    docid = subject.send :parse_docidentifier
    expect(docid).to be_instance_of Array
    expect(docid.size).to eq 1
    expect(docid[0]).to be_instance_of Relaton::Bib::Docidentifier
    expect(docid[0].content).to eq "PLATEAU Technical Report #93 1.0"
    expect(docid[0].type).to eq "PLATEAU"
    expect(docid[0].primary).to be true
  end

  it "parse_abstract" do
    abstract = subject.send :parse_abstract
    expect(abstract).to be_instance_of Array
    expect(abstract.size).to eq 1
    expect(abstract[0]).to be_instance_of Relaton::Bib::Abstract
    expect(abstract[0].content).to eq "歴史・文化・営みを継承するメタバース体験の構築の技術資料 (2023年度)"
  end

  it "parse_edition" do
    edition = subject.send :parse_edition
    expect(edition).to be_instance_of Relaton::Bib::Edition
    expect(edition.content).to eq "1.0"
    expect(edition.number).to eq "1.0"
  end

  it "parse_subdoctype" do
    subdoctype = subject.send :parse_subdoctype
    expect(subdoctype).to eq "Use Case"
  end

  it "parse_date" do
    date = subject.send :parse_date
    expect(date).to be_instance_of Array
    expect(date.size).to eq 1
    expect(date[0]).to be_instance_of Relaton::Bib::Date
    expect(date[0].at.to_s).to eq "2024-03-29"
  end

  it "parse_source" do
    link = subject.send :parse_source
    expect(link).to be_instance_of Array
    expect(link.size).to eq 1
    expect(link[0]).to be_instance_of Relaton::Bib::Uri
    expect(link[0].content).to eq(
      "https://www.mlit.go.jp/plateau/file/libraries/doc/plateau_tech_doc_0093_ver01.pdf"
    )
    expect(link[0].type).to eq "pdf"
  end

  it "parse_keyword" do
    keyword = subject.send :parse_keyword
    expect(keyword).to be_instance_of Array
    expect(keyword.size).to eq 4
    expect(keyword[0]).to be_instance_of Relaton::Bib::Keyword
    expect(keyword[0].vocab.content).to eq "Unreal Engine"
  end

  it "parse_ext" do
    ext = subject.send :parse_ext
    expect(ext).to be_instance_of Relaton::Plateau::Ext
    expect(ext.doctype).to be_instance_of Relaton::Plateau::Doctype
    expect(ext.doctype.content).to eq "technical-report"
    expect(ext.subdoctype).to eq "Use Case"
    expect(ext.flavor).to eq "plateau"
    expect(ext.filesize).to eq 22005029
    expect(ext.structuredidentifier[0]).to be_instance_of Relaton::Bib::StructuredIdentifier
    expect(ext.structuredidentifier[0].type).to eq "Technical Report"
    expect(ext.structuredidentifier[0].klass).to eq "Use Case"
    expect(ext.structuredidentifier[0].agency).to eq ["PLATEAU"]
    expect(ext.structuredidentifier[0].docnumber).to eq "93"
  end

  context "@errors guards" do
    let(:errors) do
      {
        tr_docnumber: true, tr_abstract: true, tr_date: true,
        tr_source: true, tr_keyword: true, tr_subdoctype: true,
        tr_filesize: true
      }
    end
    subject { described_class.new entry, errors }

    context "with valid data" do
      it "sets :tr_docnumber to false" do
        subject.send(:parse_docnumber)
        expect(errors[:tr_docnumber]).to be false
      end

      it "sets :tr_abstract to false" do
        subject.send(:parse_abstract)
        expect(errors[:tr_abstract]).to be false
      end

      it "sets :tr_date to false" do
        subject.send(:parse_date)
        expect(errors[:tr_date]).to be false
      end

      it "sets :tr_source to false" do
        subject.send(:parse_source)
        expect(errors[:tr_source]).to be false
      end

      it "sets :tr_keyword to false" do
        subject.send(:parse_keyword)
        expect(errors[:tr_keyword]).to be false
      end

      it "sets :tr_subdoctype to false" do
        subject.send(:parse_subdoctype)
        expect(errors[:tr_subdoctype]).to be false
      end

      it "sets :tr_filesize to false" do
        subject.send(:filesize)
        expect(errors[:tr_filesize]).to be false
      end
    end

    context "with missing data" do
      it "keeps :tr_docnumber as true when slug is nil" do
        entry["slug"] = nil
        subject.send(:parse_docnumber)
        expect(errors[:tr_docnumber]).to be true
      end

      it "keeps :tr_abstract as true when subtitle is nil" do
        entry["technicalReport"]["subtitle"] = nil
        subject.send(:parse_abstract)
        expect(errors[:tr_abstract]).to be true
      end

      it "keeps :tr_date as true when date is nil" do
        entry["date"] = nil
        subject.send(:parse_date)
        expect(errors[:tr_date]).to be true
      end

      it "keeps :tr_source as true when pdf is nil" do
        entry["technicalReport"]["pdf"] = nil
        subject.send(:parse_source)
        expect(errors[:tr_source]).to be true
      end

      it "keeps :tr_keyword as true when tags are empty" do
        entry["globalTags"]["nodes"] = []
        subject.send(:parse_keyword)
        expect(errors[:tr_keyword]).to be true
      end

      it "keeps :tr_subdoctype as true when categories are empty" do
        entry["technicalReportCategories"]["nodes"] = []
        subject.send(:parse_subdoctype)
        expect(errors[:tr_subdoctype]).to be true
      end

      it "keeps :tr_filesize as true when filesize is nil" do
        entry["technicalReport"]["filesize"] = nil
        subject.send(:filesize)
        expect(errors[:tr_filesize]).to be true
      end
    end

    context "when errors key is not pre-set" do
      let(:errors) { {} }

      it "does not create error keys" do
        subject.send(:parse_docnumber)
        subject.send(:parse_abstract)
        subject.send(:parse_date)
        subject.send(:parse_source)
        subject.send(:parse_keyword)
        subject.send(:parse_subdoctype)
        subject.send(:filesize)
        expect(errors).to be_empty
      end
    end
  end
end
