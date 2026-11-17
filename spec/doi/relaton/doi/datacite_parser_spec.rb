describe Relaton::Doi::DataciteParser do
  let(:attrs) do
    {
      "doi" => "10.5281/zenodo.123",
      "url" => "https://zenodo.org/record/123",
      "titles" => [
        { "title" => "Main title", "lang" => "en" },
        { "title" => "A subtitle", "titleType" => "Subtitle" },
        { "title" => "Titre", "titleType" => "TranslatedTitle", "lang" => "fr" },
      ],
      "creators" => [
        {
          "name" => "Deshpande, Kiran", "nameType" => "Personal",
          "givenName" => "Kiran", "familyName" => "Deshpande",
          "affiliation" => ["University of the Arts London"],
          "nameIdentifiers" => [
            { "nameIdentifier" => "https://orcid.org/0000-0002-1825-0097",
              "nameIdentifierScheme" => "ORCID" },
          ]
        },
        { "name" => "Project Jupyter", "nameType" => "Organizational" },
        { "name" => "Binder, Project", "affiliation" => [{ "name" => "Jupyter" }] },
      ],
      "contributors" => [
        { "name" => "Doe, Jane", "nameType" => "Personal", "givenName" => "Jane",
          "familyName" => "Doe", "contributorType" => "Editor" },
        { "name" => "CERN", "nameType" => "Organizational",
          "contributorType" => "HostingInstitution" },
      ],
      "publisher" => "Zenodo",
      "publicationYear" => 2019,
      "dates" => [
        { "date" => "2019-06-09", "dateType" => "Issued" },
        { "date" => "2019-06-01", "dateType" => "Created" },
        { "date" => "2019-07-01/2019-08-01", "dateType" => "Collected" },
      ],
      "language" => "en",
      "types" => { "bibtex" => "misc", "resourceTypeGeneral" => "Software" },
      "descriptions" => [
        { "description" => "An abstract.", "descriptionType" => "Abstract", "lang" => "en" },
        { "description" => "Methods.", "descriptionType" => "Methods" },
      ],
      "relatedIdentifiers" => [
        { "relationType" => "IsVersionOf", "relatedIdentifier" => "10.5281/zenodo.122",
          "relatedIdentifierType" => "DOI" },
        { "relationType" => "IsSourceOf", "relatedIdentifier" => "https://mybinder.org/x",
          "relatedIdentifierType" => "URL" },
        { "relationType" => "IsFooOf", "relatedIdentifier" => "10.1/x",
          "relatedIdentifierType" => "DOI" },
      ],
    }
  end

  subject(:item) { described_class.parse attrs }

  it { is_expected.to be_instance_of Relaton::Bib::ItemData }

  it "maps the resource type" do
    expect(item.type).to eq "software"
  end

  it "keeps today as fetched" do
    expect(item.fetched.to_s).to eq Date.today.to_s
  end

  it "maps the titles" do
    expect(item.title.map { |t| [t.type, t.content, t.language] }).to eq [
      ["main", "Main title", "en"], ["subtitle", "A subtitle", nil],
      ["main", "Titre", "fr"]
    ]
  end

  it "makes the DOI the primary docidentifier" do
    id = item.docidentifier.first
    expect([id.type, id.content, id.primary]).to eq ["DOI", "10.5281/zenodo.123", true]
  end

  it "maps the dates DataCite types as Relaton does" do
    expect(item.date.map { |d| [d.type, d.at.to_s] })
      .to eq [%w[issued 2019-06-09], %w[created 2019-06-01]]
  end

  it "maps a date range" do
    attrs["dates"] = [{ "date" => "2019-01-01/2020-02-02", "dateType" => "Created" },
                      { "date" => "2019-03/", "dateType" => "Updated" }]
    expect(item.date.map { |d| [d.type, d.from.to_s, d.to&.to_s] })
      .to eq [["issued", "", nil], %w[created 2019-01-01 2020-02-02], ["updated", "2019-03", nil]]
  end

  it "skips a free-text date it cannot read" do
    attrs["dates"] = [{ "date" => "Spring 2019", "dateType" => "Issued" }]
    expect(item.date.map { |d| [d.type, d.at.to_s] }).to eq [%w[issued 2019]]
  end

  it "falls back to the publication year" do
    attrs.delete "dates"
    expect(item.date.map { |d| [d.type, d.at.to_s] }).to eq [%w[issued 2019]]
  end

  it "makes the URL the src source" do
    expect(item.source.map { |s| [s.type, s.content.to_s] })
      .to eq [["src", "https://zenodo.org/record/123"]]
  end

  it "keeps only the Abstract descriptions" do
    expect(item.abstract.map(&:content)).to eq ["An abstract."]
  end

  it "keeps the language" do
    expect(item.language).to eq ["en"]
  end

  context "contributors" do
    let(:contribs) { item.contributor }

    it "makes a personal creator an author with names, affiliation and ORCID" do
      person = contribs[0].person
      expect(contribs[0].role.map(&:type)).to eq ["author"]
      expect(person.name.surname.content).to eq "Deshpande"
      expect(person.name.forename.map(&:content)).to eq ["Kiran"]
      expect(person.identifier.map { |i| [i.type, i.content] })
        .to eq [["orcid", "https://orcid.org/0000-0002-1825-0097"]]
      expect(person.affiliation.first.organization.name.first.content)
        .to eq "University of the Arts London"
    end

    it "makes an organizational creator an author organization" do
      expect(contribs[1].organization.name.first.content).to eq "Project Jupyter"
    end

    it "splits the name of a creator with no nameType" do
      person = contribs[2].person
      expect(person.name.surname.content).to eq "Binder"
      expect(person.affiliation.first.organization.name.first.content).to eq "Jupyter"
    end

    it "makes an Editor contributor an editor" do
      expect(contribs[3].role.map(&:type)).to eq ["editor"]
      expect(contribs[3].person.name.surname.content).to eq "Doe"
    end

    it "leaves out a contributor type that has no Relaton role" do
      names = contribs.map { |c| (c.person&.name&.surname || c.organization.name.first).content }
      expect(names).not_to include "CERN"
    end

    it "maps a Distributor and a Sponsor" do
      attrs["contributors"] = [
        { "name" => "ACME", "nameType" => "Organizational", "contributorType" => "Distributor" },
        { "name" => "Fund", "nameType" => "Organizational", "contributorType" => "Sponsor" },
      ]
      expect(contribs[3..4].map { |c| c.role.first.type }).to eq %w[distributor enabler]
    end

    it "skips a creator with no name" do
      attrs["creators"] = [{ "nameType" => "Organizational" }, { "nameType" => "Personal" },
                           { "name" => " " }]
      expect(contribs.map { |c| c.role.first.type }).to eq %w[editor publisher]
    end

    it "makes the publisher a publisher organization" do
      expect(contribs.last.role.map(&:type)).to eq ["publisher"]
      expect(contribs.last.organization.name.first.content).to eq "Zenodo"
    end

    it "skips a DataCite placeholder publisher" do
      attrs["publisher"] = "(:unav)"
      expect(contribs.map { |c| c.role.first.type }).not_to include "publisher"
    end

    it "reads a publisher object" do
      attrs["publisher"] = { "name" => "Zenodo" }
      expect(contribs.last.organization.name.first.content).to eq "Zenodo"
    end
  end

  context "relations" do
    it "maps a DOI related identifier" do
      rel = item.relation.first
      expect(rel.type).to eq "editionOf"
      expect(rel.bibitem.docidentifier.first.content).to eq "10.5281/zenodo.122"
      expect(rel.bibitem.docidentifier.first.type).to eq "DOI"
    end

    it "skips an identifier that is not a DOI" do
      expect(item.relation.size).to eq 2
    end

    it "keeps an unknown relation type as related, with a description" do
      rel = item.relation.last
      expect(rel.type).to eq "related"
      expect(rel.description.content).to eq "IsFooOf"
    end
  end

  context "types" do
    {
      { "resourceTypeGeneral" => "Dataset" } => "dataset",
      { "resourceTypeGeneral" => "Dissertation" } => "thesis",
      { "resourceTypeGeneral" => "Text", "bibtex" => "phdthesis" } => "thesis",
      { "resourceTypeGeneral" => "Text", "bibtex" => "article" } => "article",
      { "resourceTypeGeneral" => "Other", "bibtex" => "misc" } => "misc",
      {} => "misc",
    }.each do |types, type|
      it "maps #{types} to #{type}" do
        attrs["types"] = types
        expect(item.type).to eq type
      end
    end
  end
end
