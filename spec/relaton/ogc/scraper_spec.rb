# frozen_string_literal: true

require "relaton/ogc/data_fetcher"

describe Relaton::Ogc::Scraper do
  let(:scraper) { described_class.new({}) }

  it "parse_page" do
    hit = { "type" => :type, "title" => :title, "identifier" => :identifier,
            "date" => :date, "description" => :description }
    scraper = described_class.new(hit)
    expect(scraper).to receive(:fetch_type).with(:type)
      .and_return(type: :doctype, subtype: :subdoctype, stage: :draft)
    expect(scraper).to receive(:fetch_title).with(:title).and_return("Title")
    expect(scraper).to receive(:fetch_docid).with(:identifier).and_return(:docid)
    expect(scraper).to receive(:fetch_link).with(hit).and_return(:link)
    expect(scraper).to receive(:fetch_date).with(:date).and_return(:date)
    expect(scraper).to receive(:fetch_abstract).with(:description).and_return(:abstract)
    expect(scraper).to receive(:fetch_contributor).with(hit).and_return([])
    expect(scraper).to receive(:fetch_editorialgroup_contributor).and_return(:eg_contrib)
    expect(scraper).to receive(:fetch_edition).with(:identifier).and_return(:edition)
    expect(scraper).to receive(:fetch_status).with(:draft).and_return(:status)
    expect(scraper).to receive(:fetch_doctype).with(:doctype).and_return(:doctype)
    expect(Relaton::Ogc::ItemData).to receive(:new).with(
      type: "standard", title: "Title", docidentifier: :docid, source: :link,
      status: :status, edition: :edition, abstract: :abstract,
      contributor: [:eg_contrib], language: ["en"], script: ["Latn"],
      date: :date, ext: an_instance_of(Relaton::Ogc::Ext),
    )
    scraper.parse
  end

  it "fetch_editorialgroup_contributor" do
    contrib = scraper.send :fetch_editorialgroup_contributor
    expect(contrib).to be_instance_of Relaton::Bib::Contributor
    expect(contrib.role.first.type).to eq "author"
    expect(contrib.role.first.description.first.content).to eq "committee"
    expect(contrib.organization.name.first.content).to eq "Open Geospatial Consortium"
    expect(contrib.organization.abbreviation.content).to eq "OGC"
    expect(contrib.organization.subdivision.first.type).to eq "technical-committee"
    expect(contrib.organization.subdivision.first.name.first.content).to eq "technical"
  end

  it "fetch_title" do
    title = scraper.send :fetch_title, "Title"
    expect(title).to be_instance_of Array
    expect(title.first.content).to eq "Title"
    expect(title.first.language).to eq "en"
    expect(title.first.script).to eq "Latn"
  end

  it "fetch_docid" do
    docid = scraper.send :fetch_docid, "identifier"
    expect(docid).to be_instance_of Array
    expect(docid.first).to be_instance_of Relaton::Ogc::Docidentifier
    expect(docid.first.content).to eq "identifier"
    expect(docid.first.type).to eq "OGC"
    expect(docid.first.primary).to be true
  end

  context "fetch_link" do
    it "URI and URL pdf type" do
      hit = { "URI" => "uri", "URL" => "portal.ogc.org" }
      link = scraper.send :fetch_link, hit
      expect(link).to be_instance_of Array
      expect(link.size).to eq 2
      expect(link.first).to be_instance_of Relaton::Bib::Uri
      expect(link.first.type).to eq "src"
      expect(link.first.content.to_s).to eq "uri"
      expect(link.last).to be_instance_of Relaton::Bib::Uri
      expect(link.last.type).to eq "pdf"
      expect(link.last.content.to_s).to eq "portal.ogc.org"
    end

    it "URI is empty & URL type is html" do
      hit = { "URI" => "", "URL" => "www.w3.org" }
      link = scraper.send :fetch_link, hit
      expect(link.first.type).to eq "html"
      expect(link.first.content.to_s).to eq "www.w3.org"
    end

    it "URI only" do
      hit = { "URI" => "uri" }
      link = scraper.send :fetch_link, hit
      expect(link).to be_instance_of Array
      expect(link.size).to eq 1
      expect(link.first).to be_instance_of Relaton::Bib::Uri
      expect(link.first.type).to eq "src"
      expect(link.first.content.to_s).to eq "uri"
    end

    it "URL only" do
      hit = { "URL" => "url.doc" }
      link = scraper.send :fetch_link, hit
      expect(link).to be_instance_of Array
      expect(link.size).to eq 1
      expect(link.first).to be_instance_of Relaton::Bib::Uri
      expect(link.first.type).to eq "doc"
      expect(link.first.content.to_s).to eq "url.doc"
    end
  end

  it "fetch_type" do
    type = scraper.send :fetch_type, "D-CAN"
    expect(type).to eq type: "standard", subtype: "general", stage: "draft"
  end

  it "fetch_doctype" do
    doctype = scraper.send :fetch_doctype, "standard"
    expect(doctype).to be_instance_of Relaton::Ogc::Doctype
    expect(doctype.content).to eq "standard"
  end

  context "fetch_status" do
    it do
      status = scraper.send :fetch_status, "draft"
      expect(status).to be_instance_of Relaton::Bib::Status
      expect(status.stage.content).to eq "draft"
    end

    it "nil" do
      expect(scraper.send(:fetch_status, nil)).to be_nil
    end
  end

  it "fetch_edition" do
    edition = scraper.send(:fetch_edition, "r5")
    expect(edition).to be_instance_of Relaton::Bib::Edition
    expect(edition.content).to eq "5"
  end

  it "fetch_edition nil" do
    expect(scraper.send(:fetch_edition, "nope")).to be_nil
  end

  it "fetch_abstract" do
    abstract = scraper.send :fetch_abstract, "description"
    expect(abstract).to be_instance_of Array
    expect(abstract.first).to be_instance_of Relaton::Bib::Abstract
    expect(abstract.first.content).to eq "description"
    expect(abstract.first.language).to eq "en"
    expect(abstract.first.script).to eq "Latn"
  end

  it "fetch_contributor" do
    doc = { "creator" => "Person1, Person2", "publisher" => "Org" }
    expect(scraper).to receive(:person_contrib).with("Person1").and_return(:person1)
    expect(scraper).to receive(:person_contrib).with("Person2").and_return(:person2)
    expect(scraper).to receive(:org_contrib).with("Org").and_return(:org)
    contrib = scraper.send :fetch_contributor, doc
    expect(contrib).to eq %i[person1 person2 org]
  end

  it "person_contrib" do
    contrib = scraper.send :person_contrib, "Person"
    expect(contrib).to be_instance_of Relaton::Bib::Contributor
    expect(contrib.person).to be_instance_of Relaton::Bib::Person
    expect(contrib.person.name.completename.content).to eq "Person"
    expect(contrib.role.first.type).to eq "author"
  end

  it "org_contrib" do
    contrib = scraper.send :org_contrib, "Org"
    expect(contrib).to be_instance_of Relaton::Bib::Contributor
    expect(contrib.organization).to be_instance_of Relaton::Bib::Organization
    expect(contrib.organization.name.first.content).to eq "Org"
    expect(contrib.role.first.type).to eq "publisher"
  end

  context "fetch_date" do
    it do
      date = scraper.send :fetch_date, "2019-01-01"
      expect(date).to be_instance_of Array
      expect(date.first).to be_instance_of Relaton::Bib::Date
      expect(date.first.at.to_s).to eq "2019-01-01"
    end

    it "no date" do
      expect(scraper.send(:fetch_date, nil)).to eq []
    end
  end

  context "errors guards" do
    let(:scraper) { described_class.new({}, Hash.new(true)) }
    let(:errors) { scraper.instance_variable_get(:@errors) }

    it "fetch_title clears error on success" do
      scraper.send :fetch_title, "Title"
      expect(errors[:title]).to be false
    end

    it "fetch_title clears error even with empty string" do
      scraper.send :fetch_title, ""
      expect(errors[:title]).to be false
    end

    it "fetch_docid clears error on success" do
      scraper.send :fetch_docid, "OGC-01"
      expect(errors[:docid]).to be false
    end

    it "fetch_docid keeps error on empty identifier" do
      scraper.send :fetch_docid, ""
      expect(errors[:docid]).to be true
    end

    it "fetch_docid keeps error on nil identifier" do
      scraper.send :fetch_docid, nil
      expect(errors[:docid]).to be true
    end

    it "fetch_link clears error when links present" do
      scraper.send :fetch_link, { "URI" => "http://example.com" }
      expect(errors[:link]).to be false
    end

    it "fetch_link keeps error when no links" do
      scraper.send :fetch_link, {}
      expect(errors[:link]).to be true
    end

    it "fetch_status clears error on success" do
      scraper.send :fetch_status, "draft"
      expect(errors[:status]).to be false
    end

    it "fetch_status keeps error on nil stage" do
      scraper.send :fetch_status, nil
      expect(errors[:status]).to be true
    end

    it "fetch_edition clears error on success" do
      scraper.send :fetch_edition, "r5"
      expect(errors[:edition]).to be false
    end

    it "fetch_edition keeps error when no edition" do
      scraper.send :fetch_edition, "nope"
      expect(errors[:edition]).to be true
    end

    it "fetch_abstract clears error on success" do
      scraper.send :fetch_abstract, "Some description"
      expect(errors[:abstract]).to be false
    end

    it "fetch_abstract keeps error on empty description" do
      scraper.send :fetch_abstract, ""
      expect(errors[:abstract]).to be true
    end

    it "fetch_abstract keeps error on nil description" do
      scraper.send :fetch_abstract, nil
      expect(errors[:abstract]).to be true
    end

    it "fetch_contributor clears error on success" do
      scraper.send :fetch_contributor, { "creator" => "Person" }
      expect(errors[:contributor]).to be false
    end

    it "fetch_contributor keeps error when no contributors" do
      scraper.send :fetch_contributor, {}
      expect(errors[:contributor]).to be true
    end

    it "fetch_date clears error on success" do
      scraper.send :fetch_date, "2019-01-01"
      expect(errors[:date]).to be false
    end

    it "fetch_date keeps error on nil date" do
      scraper.send :fetch_date, nil
      expect(errors[:date]).to be true
    end
  end
end
