# frozen_string_literal: true

describe Relaton::Ogc::Scraper do
  it "parse_page" do
    hit = { "type" => :type, "title" => :title, "identifier" => :identifier,
            "date" => :date, "description" => :description }
    expect(described_class).to receive(:fetch_type).with(:type)
      .and_return(type: :doctype, subtype: :subdoctype, stage: :draft)
    expect(described_class).to receive(:fetch_title).with(:title).and_return("Title")
    expect(described_class).to receive(:fetch_docid).with(:identifier).and_return(:docid)
    expect(described_class).to receive(:fetch_link).with(hit).and_return(:link)
    expect(described_class).to receive(:fetch_date).with(:date).and_return(:date)
    expect(described_class).to receive(:fetch_abstract).with(:description).and_return(:abstract)
    expect(described_class).to receive(:fetch_contributor).with(hit).and_return([])
    expect(described_class).to receive(:fetch_editorialgroup_contributor).and_return(:eg_contrib)
    expect(described_class).to receive(:fetch_edition).with(:identifier).and_return(:edition)
    expect(described_class).to receive(:fetch_status).with(:draft).and_return(:status)
    expect(described_class).to receive(:fetch_doctype).with(:doctype).and_return(:doctype)
    expect(Relaton::Ogc::Item).to receive(:new).with(
      type: "standard", title: "Title", docidentifier: :docid, source: :link,
      status: :status, edition: :edition, abstract: :abstract,
      contributor: [:eg_contrib], language: ["en"], script: ["Latn"],
      date: :date, ext: an_instance_of(Relaton::Ogc::Ext),
    )
    described_class.parse_page hit
  end

  it "fetch_editorialgroup_contributor" do
    contrib = described_class.send :fetch_editorialgroup_contributor
    expect(contrib).to be_instance_of Relaton::Bib::Contributor
    expect(contrib.role.first.type).to eq "author"
    expect(contrib.role.first.description.first.content).to eq "committee"
    expect(contrib.organization.name.first.content).to eq "Open Geospatial Consortium"
    expect(contrib.organization.abbreviation.content).to eq "OGC"
    expect(contrib.organization.subdivision.first.type).to eq "technical-committee"
    expect(contrib.organization.subdivision.first.name.first.content).to eq "technical"
  end

  it "fetch_title" do
    title = described_class.send :fetch_title, "Title"
    expect(title).to be_instance_of Array
    expect(title.first.content).to eq "Title"
    expect(title.first.language).to eq "en"
    expect(title.first.script).to eq "Latn"
  end

  it "fetch_docid" do
    docid = described_class.send :fetch_docid, "identifier"
    expect(docid).to be_instance_of Array
    expect(docid.first).to be_instance_of Relaton::Bib::Docidentifier
    expect(docid.first.content).to eq "identifier"
    expect(docid.first.type).to eq "OGC"
    expect(docid.first.primary).to be true
  end

  context "fetch_link" do
    it "URI and URL pdf type" do
      hit = { "URI" => "uri", "URL" => "portal.ogc.org" }
      link = described_class.send :fetch_link, hit
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
      link = described_class.send :fetch_link, hit
      expect(link.first.type).to eq "html"
      expect(link.first.content.to_s).to eq "www.w3.org"
    end

    it "URI only" do
      hit = { "URI" => "uri" }
      link = described_class.send :fetch_link, hit
      expect(link).to be_instance_of Array
      expect(link.size).to eq 1
      expect(link.first).to be_instance_of Relaton::Bib::Uri
      expect(link.first.type).to eq "src"
      expect(link.first.content.to_s).to eq "uri"
    end

    it "URL only" do
      hit = { "URL" => "url.doc" }
      link = described_class.send :fetch_link, hit
      expect(link).to be_instance_of Array
      expect(link.size).to eq 1
      expect(link.first).to be_instance_of Relaton::Bib::Uri
      expect(link.first.type).to eq "doc"
      expect(link.first.content.to_s).to eq "url.doc"
    end
  end

  it "fetch_type" do
    type = described_class.send :fetch_type, "D-CAN"
    expect(type).to eq type: "standard", subtype: "general", stage: "draft"
  end

  it "fetch_doctype" do
    doctype = described_class.send :fetch_doctype, "standard"
    expect(doctype).to be_instance_of Relaton::Ogc::Doctype
    expect(doctype.content).to eq "standard"
  end

  context "fetch_status" do
    it do
      status = described_class.send :fetch_status, "draft"
      expect(status).to be_instance_of Relaton::Bib::Status
      expect(status.stage.content).to eq "draft"
    end

    it "nil" do
      expect(described_class.send(:fetch_status, nil)).to be_nil
    end
  end

  it "fetch_edition" do
    edition = described_class.send(:fetch_edition, "r5")
    expect(edition).to be_instance_of Relaton::Bib::Edition
    expect(edition.content).to eq "5"
  end

  it "fetch_edition nil" do
    expect(described_class.send(:fetch_edition, "nope")).to be_nil
  end

  it "fetch_abstract" do
    abstract = described_class.send :fetch_abstract, "description"
    expect(abstract).to be_instance_of Array
    expect(abstract.first).to be_instance_of Relaton::Bib::LocalizedMarkedUpString
    expect(abstract.first.content).to eq "description"
    expect(abstract.first.language).to eq "en"
    expect(abstract.first.script).to eq "Latn"
  end

  it "fetch_contributor" do
    doc = { "creator" => "Person1, Person2", "publisher" => "Org" }
    expect(described_class).to receive(:person_contrib).with("Person1").and_return(:person1)
    expect(described_class).to receive(:person_contrib).with("Person2").and_return(:person2)
    expect(described_class).to receive(:org_contrib).with("Org").and_return(:org)
    contrib = described_class.send :fetch_contributor, doc
    expect(contrib).to eq %i[person1 person2 org]
  end

  it "person_contrib" do
    contrib = described_class.send :person_contrib, "Person"
    expect(contrib).to be_instance_of Relaton::Bib::Contributor
    expect(contrib.person).to be_instance_of Relaton::Bib::Person
    expect(contrib.person.name.completename.content).to eq "Person"
    expect(contrib.role.first.type).to eq "author"
  end

  it "org_contrib" do
    contrib = described_class.send :org_contrib, "Org"
    expect(contrib).to be_instance_of Relaton::Bib::Contributor
    expect(contrib.organization).to be_instance_of Relaton::Bib::Organization
    expect(contrib.organization.name.first.content).to eq "Org"
    expect(contrib.role.first.type).to eq "publisher"
  end

  context "fetch_date" do
    it do
      date = described_class.send :fetch_date, "2019-01-01"
      expect(date).to be_instance_of Array
      expect(date.first).to be_instance_of Relaton::Bib::Date
      expect(date.first.at.to_s).to eq "2019-01-01"
    end

    it "no date" do
      expect(described_class.send(:fetch_date, nil)).to eq []
    end
  end
end
