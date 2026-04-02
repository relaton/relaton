require "relaton/plateau/data_fetcher"

RSpec.describe Relaton::Plateau::HandbookParser do
  let(:version) do
    {
      "title" => "第3.0版 実証環境構築マニュアル",
      "date" => "2023.4.7",
      "pdf" => "https://www.mlit.go.jp/plateau/file/libraries/doc/plateau_doc_0009_ver03.pdf",
      "filesize" => "16124297",
      "html" => nil
    }
  end

  let(:entry) do
    {
      "id" => "cG9zdDo5ODQ=",
      "slug" => "09",
      "handbook" => {
        "title" => "PLATEAU VIEW構築マニュアル",
        "description" => "3D City Model Demonstration Manual<br />\r\n3D都市モデルの可視化環境構築及びデータ重畳のための仕様・手順等のマニュアル<br />\r\n",
        "thumbnail" => {
          "mediaItemUrl" => "/plateau/uploads/2024/04/plateau_doc_0009_ver04.jpg"
        },
      }
    }
  end

  let(:doctype) { "handbook" }
  subject do
    Relaton::Plateau::HandbookParser.new(
      version: version, entry: entry, doctype: doctype
    )
  end

  it "creates handbook" do
    expect(subject.instance_variable_get(:@version)).to be version
    expect(subject.instance_variable_get(:@entry)).to be entry
    expect(subject.instance_variable_get(:@item)).to be entry["handbook"]
    expect(subject.instance_variable_get(:@doctype)).to eq doctype
  end

  context "parse" do
    let(:bibitem) { subject.parse }
    it { expect(bibitem).to be_instance_of Relaton::Plateau::ItemData }
    it { expect(bibitem.docidentifier[0]).to be_instance_of Relaton::Bib::Docidentifier }
    it { expect(bibitem.docnumber).to eq "Handbook #09 3.0" }
    it { expect(bibitem.title[0]).to be_instance_of Relaton::Bib::Title }
    it { expect(bibitem.abstract[0]).to be_instance_of Relaton::Bib::Abstract }
    it { expect(bibitem.edition).to be_instance_of Relaton::Bib::Edition }
    it { expect(bibitem.ext).to be_instance_of Relaton::Plateau::Ext }
    it { expect(bibitem.ext.doctype).to be_instance_of Relaton::Plateau::Doctype }
    it { expect(bibitem.ext.subdoctype).to be_nil }
    it { expect(bibitem.date[0]).to be_instance_of Relaton::Bib::Date }
    it { expect(bibitem.source[0]).to be_instance_of Relaton::Bib::Uri }
    it { expect(bibitem.contributor[0]).to be_instance_of Relaton::Bib::Contributor }
    it { expect(bibitem.ext.filesize).to eq 16124297 }
    it { expect(bibitem.keyword).to eq [] }
    it { expect(bibitem.ext.structuredidentifier[0]).to be_instance_of Relaton::Bib::StructuredIdentifier }
  end

  it "parse_docidentifier" do
    docid = subject.send :parse_docidentifier
    expect(docid).to be_instance_of Array
    expect(docid.size).to eq 1
    expect(docid[0]).to be_instance_of Relaton::Bib::Docidentifier
    expect(docid[0].content).to eq "PLATEAU Handbook #09 3.0"
    expect(docid[0].type).to eq "PLATEAU"
    expect(docid[0].primary).to be true
  end

  it "parse_title" do
    title = subject.send :parse_title
    expect(title).to be_instance_of Array
    expect(title.size).to eq 1
    expect(title[0]).to be_instance_of Relaton::Bib::Title
    expect(title[0].content).to eq "PLATEAU VIEW構築マニュアル"
    expect(title[0].language).to eq "ja"
    expect(title[0].script).to eq "Jpan"
  end

  context "when title is English" do
    let(:entry) do
      {
        "slug" => "00",
        "handbook" => {
          "title" => "PLATEAU Guidebook",
          "description" => "Guidance on the Installation for 3D City Model<br />\r\n地方自治体担当者や民間事業者等に向けた 3D都市モデル導入のためのガイダンス",
          "thumbnail" => {
            "mediaItemUrl" => "/plateau/uploads/2024/04/handbook_00_img--scaled.jpg"
          },
        }
      }
    end

    it "parse_title returns 1 English title" do
      title = subject.send :parse_title
      expect(title).to be_instance_of Array
      expect(title.size).to eq 1
      expect(title[0].content).to eq "PLATEAU Guidebook"
      expect(title[0].language).to eq "en"
      expect(title[0].script).to eq "Latn"
    end

    it "parse_abstract returns 2 abstracts from description" do
      abstract_result = subject.send :parse_abstract
      expect(abstract_result).to be_instance_of Array
      expect(abstract_result.size).to eq 2
      expect(abstract_result[0].content).to eq "Guidance on the Installation for 3D City Model"
      expect(abstract_result[0].language).to eq "en"
      expect(abstract_result[0].script).to eq "Latn"
      expect(abstract_result[1].content).to eq "地方自治体担当者や民間事業者等に向けた 3D都市モデル導入のためのガイダンス"
      expect(abstract_result[1].language).to eq "ja"
      expect(abstract_result[1].script).to eq "Jpan"
    end
  end

  it "parse_abstract" do
    abstract = subject.send :parse_abstract
    expect(abstract).to be_instance_of Array
    expect(abstract.size).to eq 2
    expect(abstract[0]).to be_instance_of Relaton::Bib::Abstract
    expect(abstract[0].content).to eq "3D City Model Demonstration Manual"
    expect(abstract[0].language).to eq "en"
    expect(abstract[0].script).to eq "Latn"
    expect(abstract[0]).to be_instance_of Relaton::Bib::Abstract
    expect(abstract[1].content).to eq "3D都市モデルの可視化環境構築及びデータ重畳のための仕様・手順等のマニュアル"
    expect(abstract[1].language).to eq "ja"
    expect(abstract[1].script).to eq "Jpan"
  end

  it "parse_edition" do
    edition = subject.send :parse_edition
    expect(edition).to be_instance_of Relaton::Bib::Edition
    expect(edition.content).to eq "3.0"
    expect(edition.number).to eq "3.0"
  end

  it "parse_date" do
    date = subject.send :parse_date
    expect(date).to be_instance_of Array
    expect(date.size).to eq 1
    expect(date[0]).to be_instance_of Relaton::Bib::Date
    expect(date[0].type).to eq "published"
    expect(date[0].at.to_s).to eq "2023-04-07"
  end

  context "parse_source" do
    it "pdf only" do
      link = subject.send :parse_source
      expect(link).to be_instance_of Array
      expect(link.size).to eq 1
      expect(link[0]).to be_instance_of Relaton::Bib::Uri
      expect(link[0].content).to eq "https://www.mlit.go.jp/plateau/file/libraries/doc/plateau_doc_0009_ver03.pdf"
      expect(link[0].type).to eq "pdf"
    end

    it "pdf and html" do
      version["html"] = "https://example.com/1.0.html"
      link = subject.send :parse_source
      expect(link).to be_instance_of Array
      expect(link.size).to eq 2
      expect(link[0]).to be_instance_of Relaton::Bib::Uri
      expect(link[0].content).to eq "https://www.mlit.go.jp/plateau/file/libraries/doc/plateau_doc_0009_ver03.pdf"
      expect(link[0].type).to eq "pdf"
      expect(link[1]).to be_instance_of Relaton::Bib::Uri
      expect(link[1].content).to eq "https://example.com/1.0.html"
      expect(link[1].type).to eq "html"
    end
  end

  it "parse_ext" do
    ext = subject.send :parse_ext
    expect(ext).to be_instance_of Relaton::Plateau::Ext
    expect(ext.doctype).to be_instance_of Relaton::Plateau::Doctype
    expect(ext.doctype.content).to eq "handbook"
    expect(ext.flavor).to eq "plateau"
    expect(ext.filesize).to eq 16124297
    expect(ext.structuredidentifier[0]).to be_instance_of Relaton::Bib::StructuredIdentifier
    expect(ext.structuredidentifier[0].type).to eq "Handbook"
    expect(ext.structuredidentifier[0].agency).to eq ["PLATEAU"]
    expect(ext.structuredidentifier[0].docnumber).to eq "09"
    expect(ext.structuredidentifier[0].edition).to eq "3.0"
  end

  context "@errors guards" do
    let(:errors) do
      {
        hb_docnumber: true, hb_abstract: true, hb_edition: true,
        hb_date: true, hb_source: true, hb_filesize: true
      }
    end
    subject do
      described_class.new(
        version: version, entry: entry, doctype: doctype, errors: errors
      )
    end

    context "with valid data" do
      it "sets :hb_docnumber to false" do
        subject.send(:parse_docnumber)
        expect(errors[:hb_docnumber]).to be false
      end

      it "sets :hb_abstract to false" do
        subject.send(:parse_abstract)
        expect(errors[:hb_abstract]).to be false
      end

      it "sets :hb_edition to false" do
        subject.send(:parse_edition)
        expect(errors[:hb_edition]).to be false
      end

      it "sets :hb_date to false" do
        subject.send(:parse_date)
        expect(errors[:hb_date]).to be false
      end

      it "sets :hb_source to false" do
        subject.send(:parse_source)
        expect(errors[:hb_source]).to be false
      end

      it "sets :hb_filesize to false" do
        subject.send(:filesize)
        expect(errors[:hb_filesize]).to be false
      end
    end

    context "with missing data" do
      it "keeps :hb_docnumber as true when slug is nil" do
        entry["slug"] = nil
        subject.send(:parse_docnumber)
        expect(errors[:hb_docnumber]).to be true
      end

      it "keeps :hb_abstract as true when description is nil" do
        entry["handbook"]["description"] = nil
        subject.send(:parse_abstract)
        expect(errors[:hb_abstract]).to be true
      end

      it "keeps :hb_edition as true when edition is empty" do
        version["title"] = "no version here"
        subject.send(:parse_edition)
        expect(errors[:hb_edition]).to be true
      end

      it "keeps :hb_date as true when date is nil" do
        version["date"] = nil
        subject.send(:parse_date)
        expect(errors[:hb_date]).to be true
      end

      it "keeps :hb_source as true when no links" do
        version["pdf"] = nil
        version["html"] = nil
        subject.send(:parse_source)
        expect(errors[:hb_source]).to be true
      end

      it "keeps :hb_filesize as true when filesize is nil" do
        version["filesize"] = nil
        subject.send(:filesize)
        expect(errors[:hb_filesize]).to be true
      end
    end

    context "when errors key is not pre-set" do
      let(:errors) { {} }

      it "does not create error keys" do
        subject.send(:parse_docnumber)
        subject.send(:parse_abstract)
        subject.send(:parse_date)
        subject.send(:parse_source)
        subject.send(:filesize)
        expect(errors).to be_empty
      end
    end
  end
end
