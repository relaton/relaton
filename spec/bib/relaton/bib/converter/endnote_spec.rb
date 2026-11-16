require "spec_helper"

describe Relaton::Bib::Converter::Endnote do
  context ".to_item" do
    it "parses a record into an item" do
      item = described_class.to_item(<<~REFER)["Test Standard"]
        %A Austen, Jane
        %A Example Press
        %T Test Standard
        %D 2024
        %@ 2
        %I Example Press
        %K testing
        %K bibliography
        %U https://example.org/test
        %J The Journal
        %S The Series

      REFER

      expect(item.title.first.type).to eq "title-main"
      expect(item.title.first.content).to eq "Test Standard"
      expect(item.date.first.type).to eq "published"
      expect(item.date.first.at.to_s).to eq "2024"
      expect(item.edition.content).to eq "2"
      expect(item.keyword.map { |k| k.vocab.content }).to eq %w[testing bibliography]
      expect(item.source.first.content).to eq "https://example.org/test"

      authors = item.contributor.select { |c| c.role.first.type == "author" }
      expect(authors.size).to eq 2
      expect(authors[0].person.name.surname.content).to eq "Austen"
      expect(authors[0].person.name.forename.map(&:content)).to eq ["Jane"]
      expect(authors[1].organization.name.first.content).to eq "Example Press"

      publishers = item.contributor.select { |c| c.role.first.type == "publisher" }
      expect(publishers.first.organization.name.first.content).to eq "Example Press"

      journal = item.series.find { |s| s.type == "journal" }
      expect(journal.title.first.content).to eq "The Journal"
      plain = item.series.reject { |s| s.type == "journal" }
      expect(plain.first.title.first.content).to eq "The Series"
    end

    it "keys records by title" do
      items = described_class.to_item <<~REFER
        %T First
        %D 2024

        %T Second
        %D 2025

      REFER

      expect(items.keys).to eq %w[First Second]
      expect(items["Second"].date.first.at.to_s).to eq "2025"
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
    reparsed = parsed.values.first

    expect(reparsed.title.first.content).to eq "Test Standard"
    expect(reparsed.date.first.at.to_s).to eq "2024"
    author = reparsed.contributor.find { |c| c.role.first.type == "author" }
    expect(author.person.name.surname.content).to eq "Austen"
    expect(author.person.name.forename.map(&:content)).to eq ["Jane"]
    publisher = reparsed.contributor.find { |c| c.role.first.type == "publisher" }
    expect(publisher.organization.name.first.content).to eq "Example Press"
  end
end
