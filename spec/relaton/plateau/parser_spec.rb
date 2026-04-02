require "relaton/plateau/data_fetcher"

RSpec.describe Relaton::Plateau::Parser do
  let(:item) do
    {
      "title" => "3D都市モデル標準製品仕様書",
      "thumbnail" => { "mediaItemUrl" => "/plateau/uploads/2022/06/1@2x.jpg" }
    }
  end

  subject { described_class.new item }

  it "creates parser" do
    expect(subject.instance_variable_get(:@item)).to be item
  end

  it "parse_docidentifier" do
    expect(subject.send(:parse_docidentifier)[0]).to be_instance_of Relaton::Bib::Docidentifier
  end

  it "create_docid" do
    docid = subject.send(:create_docid, "id")
    expect(docid).to be_instance_of Relaton::Bib::Docidentifier
    expect(docid.type).to eq "PLATEAU"
    expect(docid.content).to eq "id"
    expect(docid.primary).to be true
  end

  it "create_abstract" do
    fs = subject.send(:create_abstract, "content", "en", "Latn")
    expect(fs).to be_instance_of Relaton::Bib::Abstract
    expect(fs.content).to eq "content"
    expect(fs.language).to eq "en"
    expect(fs.script).to eq "Latn"
  end

  it "parse_title" do
    title = subject.send(:parse_title)
    expect(title).to be_instance_of Array
    expect(title.size).to eq 1
    expect(title.first).to be_instance_of Relaton::Bib::Title
    expect(title.first.type).to eq "main"
    expect(title.first.content).to eq "3D都市モデル標準製品仕様書"
    expect(title.first.language).to eq "ja"
    expect(title.first.script).to eq "Jpan"
  end

  it "detect_lang with Japanese text" do
    expect(subject.send(:detect_lang, "3D都市モデル")).to eq ["ja", "Jpan"]
  end

  it "detect_lang with English text" do
    expect(subject.send(:detect_lang, "PLATEAU Guidebook")).to eq ["en", "Latn"]
  end

  it "parse_abstract" do
    expect(subject.send(:parse_abstract)).to eq []
  end

  it "parse_depiction" do
    depiction = subject.send(:parse_depiction)
    expect(depiction[0]).to be_instance_of Relaton::Bib::Depiction
    expect(depiction[0].scope).to eq "cover"
    expect(depiction[0].image[0]).to be_instance_of Relaton::Bib::Image
    expect(depiction[0].image[0].src).to eq "https://www.mlit.go.jp//plateau/uploads/2022/06/1@2x.jpg"
    expect(depiction[0].image[0].mimetype).to eq "image/jpeg"
  end

  it "parse_edition" do
    expect { subject.send(:parse_edition) }.to raise_error "Not implemented"
  end

  it "parse_type" do
    expect(subject.send(:parse_type)).to eq "standard"
  end

  it "parse_date" do
    expect(subject.send(:parse_date)).to eq []
  end

  it "create_date" do
    date = subject.send(:create_date, "2022-06-01")
    expect(date).to be_instance_of Relaton::Bib::Date
    expect(date.type).to eq "published"
    expect(date.at.to_s).to eq "2022-06-01"
  end

  it "parse_source" do
    expect(subject.send(:parse_source)).to eq []
  end

  it "create_link" do
    link = subject.send(:create_link, "http://example.com", "pdf")
    expect(link).to be_instance_of Relaton::Bib::Uri
    expect(link.content).to eq "http://example.com"
    expect(link.type).to eq "pdf"
  end

  it "parse_contributor" do
    contrib = subject.send(:parse_contributor)
    expect(contrib).to be_instance_of Array
    expect(contrib.size).to eq 1
    expect(contrib.first).to be_instance_of Relaton::Bib::Contributor
    expect(contrib.first.organization).to be_instance_of Relaton::Bib::Organization
    expect(contrib.first.organization.name.size).to eq 2
    expect(contrib.first.organization.name.first.content).to eq "国土交通省"
    expect(contrib.first.organization.name.first.language).to eq "ja"
    expect(contrib.first.organization.name.first.script).to eq "Jpan"
    expect(contrib.first.organization.name.last.content).to eq(
      "Japanese Ministry of Land, Infrastructure, Transport and Tourism"
    )
    expect(contrib.first.organization.name.last.language).to eq "en"
    expect(contrib.first.organization.name.last.script).to eq "Latn"
  end

  it "parse_keyword" do
    expect(subject.send(:parse_keyword)).to eq []
  end

  it "parse_ext" do
    expect { subject.send(:parse_ext) }.to raise_error "Not implemented"
  end

  context "@errors guards" do
    let(:errors) do
      { parse_docidentifier: true, title: true, parse_depiction: true, parse_contributor: true }
    end
    subject { described_class.new item, errors }

    context "with valid data" do
      it "sets :parse_docidentifier to false" do
        subject.send(:parse_docidentifier)
        expect(errors[:parse_docidentifier]).to be false
      end

      it "sets :title to false" do
        subject.send(:parse_title)
        expect(errors[:title]).to be false
      end

      it "sets :parse_depiction to false" do
        subject.send(:parse_depiction)
        expect(errors[:parse_depiction]).to be false
      end

      it "sets :parse_contributor to false" do
        subject.send(:parse_contributor)
        expect(errors[:parse_contributor]).to be false
      end
    end

    context "when errors key is not pre-set" do
      let(:errors) { {} }

      it "does not create error keys" do
        subject.send(:parse_docidentifier)
        subject.send(:parse_title)
        subject.send(:parse_depiction)
        subject.send(:parse_contributor)
        expect(errors).to be_empty
      end
    end
  end
end
