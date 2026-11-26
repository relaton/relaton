require "spec_helper"

describe Relaton::Bib::Converter::Ris do
  context ".to_item" do
    it "parses a record into an item" do
      item = described_class.to_item(<<~RIS)["ISO 1234:2024"]
        TY  - STD
        AU  - Austen, Jane
        AU  - ISO
        TI  - Test Standard
        ID  - ISO 1234:2024
        PY  - 2024
        ET  - 2
        LA  - en
        KW  - testing
        KW  - bibliography
        UR  - https://example.org/iso-1234
        PB  - Example Press
        ER  -
      RIS

      expect(item.type).to eq "standard"
      expect(item.docidentifier.first.content).to eq "ISO 1234:2024"
      expect(item.docidentifier.first.primary).to be true
      expect(item.title.first.type).to eq "title-main"
      expect(item.title.first.content).to eq "Test Standard"
      expect(item.date.first.type).to eq "published"
      expect(item.date.first.at.to_s).to eq "2024"
      expect(item.edition.content).to eq "2"
      expect(item.language).to eq ["en"]
      expect(item.keyword.map { |k| k.vocab.first.content }).to eq %w[testing bibliography]
      expect(item.source.first.content).to eq "https://example.org/iso-1234"

      authors = item.contributor.select { |c| c.role.first.type == "author" }
      expect(authors.size).to eq 2
      expect(authors[0].person.name.surname.content).to eq "Austen"
      expect(authors[0].person.name.forename.map(&:content)).to eq ["Jane"]
      expect(authors[1].organization.name.first.content).to eq "ISO"

      publishers = item.contributor.select { |c| c.role.first.type == "publisher" }
      expect(publishers.first.organization.name.first.content).to eq "Example Press"
    end

    it "parses a full PY date" do
      item = described_class.to_item(<<~RIS).values.first
        TY  - BOOK
        TI  - A Book
        PY  - 2003/07/01
        ER  -
      RIS

      expect(item.date.first.at.to_s).to eq "2003-07-01"
      expect(item.type).to eq "book"
    end

    it "keys records by ID, falling back to position" do
      items = described_class.to_item <<~RIS
        TY  - STD
        ID  - ISO 1:2024
        TI  - First
        ER  -
        TY  - BOOK
        TI  - Second
        ER  -
      RIS

      expect(items.keys).to eq ["ISO 1:2024", "record-2"]
      expect(items["ISO 1:2024"].title.first.content).to eq "First"
      expect(items["record-2"].title.first.content).to eq "Second"
    end
  end

  it "round-trips an exported record" do
    item = Relaton::Bib::Item.from_xml(<<~XML)
      <bibitem type="standard">
        <title type="title-main" language="eng">Test Standard</title>
        <docidentifier type="ISO" primary="true">ISO 1234:2024</docidentifier>
        <date type="published"><on>2024</on></date>
        <contributor>
          <role type="author"/>
          <person><name><forename>Jane</forename><surname>Austen</surname></name></person>
        </contributor>
        <contributor>
          <role type="publisher"/>
          <organization><name>Example Press</name></organization>
        </contributor>
      </bibitem>
    XML

    parsed = described_class.to_item(described_class.from_item(item))
    reparsed = parsed["ISO 1234:2024"]

    expect(reparsed.type).to eq "standard"
    expect(reparsed.title.first.content).to eq "Test Standard"
    expect(reparsed.date.first.at.to_s).to eq "2024"
    author = reparsed.contributor.find { |c| c.role.first.type == "author" }
    expect(author.person.name.surname.content).to eq "Austen"
    expect(author.person.name.forename.map(&:content)).to eq ["Jane"]
    publisher = reparsed.contributor.find { |c| c.role.first.type == "publisher" }
    expect(publisher.organization.name.first.content).to eq "Example Press"
  end
end
