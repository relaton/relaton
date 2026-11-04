# frozen_string_literal: true

require_relative "../spec_helper"
require "relaton/bib"

RSpec.describe Relaton::Render::Iso690::Renderer do
  def bib(xml)
    Relaton::Bib::Bibitem.from_xml(xml)
  end

  describe "ISO 690 clause 8.2 monographs (FARRAR example)" do
    let(:farrar) do
      bib(<<~X)
        <bibitem type="book">
          <title>Eric, or Little by Little: a tale of Roslyn School</title>
          <date type="published"><on>1971</on></date>
          <contributor><role type="author"/>
            <person><name><surname>Farrar</surname>
              <forename>Frederic</forename><forename>William</forename></name></person>
          </contributor>
          <contributor><role type="publisher"/>
            <organization><name>Hamilton</name></organization>
          </contributor>
          <place><city>London</city></place>
        </bibitem>
      X
    end

    it "renders per the standard's worked example" do
      expect(described_class.render(farrar))
        .to eq "FARRAR, Frederic William. _Eric, or Little by Little: " \
               "a tale of Roslyn School_. London: Hamilton, 1971."
    end

    it "renders a single-name creator verbatim when only completename given" do
      model = bib(<<~X)
        <bibitem type="book">
          <title>A thin book</title>
          <date type="published"><on>2000</on></date>
          <contributor><role type="author"/>
            <person><name><completename>Ada Author</completename></name></person>
          </contributor>
        </bibitem>
      X
      expect(described_class.render(model))
        .to eq "Ada Author. _A thin book_. 2000."
    end

    it "omits non-present elements (no place, no production)" do
      model = bib(<<~X)
        <bibitem type="book">
          <title>A thin book</title>
          <date type="published"><on>2000</on></date>
          <contributor><role type="author"/>
            <person><name><surname>Author</surname><forename>Ada</forename></name></person>
          </contributor>
        </bibitem>
      X
      expect(described_class.render(model))
        .to eq "AUTHOR, Ada. _A thin book_. 2000."
    end

    it "renders edition, series and identifiers in table order" do
      model = bib(<<~X)
        <bibitem type="book">
          <title>Fowler's dictionary of modern English usage</title>
          <edition>4</edition>
          <date type="published"><on>2015</on></date>
          <contributor><role type="author"/>
            <person><name><surname>Fowler</surname><forename>H. W</forename></name></person>
          </contributor>
          <contributor><role type="publisher"/>
            <organization><name>Oxford University Press</name></organization>
          </contributor>
          <place><city>Oxford</city></place>
          <docidentifier type="ISBN">978-0-19-966135-0</docidentifier>
          <series><title>Fowler dictionary series</title></series>
        </bibitem>
      X
      expect(described_class.render(model))
        .to eq "FOWLER, H. W. _Fowler's dictionary of modern English " \
               "usage_. 4th ed. _Fowler dictionary series_. " \
               "Oxford: Oxford University Press, 2015. " \
               "ISBN 978-0-19-966135-0."
    end

    it "wraps the production and authorizer slots in the kind's forms" do
      pack = File.join(Dir.mktmpdir, "slot-forms.yml").tap do |path|
        File.write(path, <<~YML)
          name: slot forms pack
          perType:
            - type: report
              template: "{{creator}}. {{title}}{{authorizer}}{{production}}. {{location}}"
              authorizer: ". {{authorizer}}"
              production: ", {{production}}"
          templates:
            reference: "{{title}}"
        YML
      end
      ieee = bib(<<~X)
        <bibitem type="standard">
          <title>Data specification</title>
          <docidentifier type="IEEE">IEEE 1234</docidentifier>
          <contributor><role type="publisher"/>
            <organization><name>Institute of Electrical and Electronics Engineers</name></organization>
          </contributor>
          <contributor><role type="author"/>
            <organization><name>Institute of Electrical and Electronics Engineers</name></organization>
          </contributor>
          <date type="published"><on>2020</on></date>
        </bibitem>
      X
      ietf = bib(<<~X)
        <bibitem type="standard">
          <title>Intellectual Property Rights in IETF Technology</title>
          <docidentifier type="IETF">RFC 3979</docidentifier>
          <contributor><role type="editor"/>
            <person><name><completename>S. Bradner</completename></name></person>
          </contributor>
          <contributor><role type="authorizer"/>
            <organization><name>RFC Series</name></organization>
          </contributor>
          <date type="published"><on>2005</on></date>
        </bibitem>
      X
      renderer = described_class.new(style: pack)
      # the authorizer carries the period, the production the comma —
      # each slot's separator lives in its own form
      expect(renderer.render(ieee))
        .to include "_Data specification_, Institute of Electrical"
      expect(renderer.render(ietf))
        .to include "_Intellectual Property Rights in IETF " \
          "Technology_. RFC Series"
    end

    it "renders a %-template size unit with the value at its %" do
      pack = File.join(Dir.mktmpdir, "size-pack.yml").tap do |path|
        File.write(path, <<~YML)
          name: size pack
          scheme:
            locale:
              labels:
                size_volume: "% vol."
          templates:
            reference: "{{title}}. {{size}}."
        YML
      end
      model = bib(<<~X)
        <bibitem type="book">
          <title>A one-volume work</title>
          <size><value type="volume">1</value></size>
          <date type="published"><on>2019</on></date>
        </bibitem>
      X
      expect(described_class.new(style: pack).render(model))
        .to eq "_A one-volume work_. 1 vol."
    end

    it "lets the pack's exact edition word outrank the caller's ordinal template" do
      pack = File.join(Dir.mktmpdir, "edition-words.yml").tap do |path|
        File.write(path, <<~YML)
          name: edition words
          scheme:
            locale:
              labels:
                edition_1: "first edition"
          templates:
            reference: "{{title}}. {{edition}}."
        YML
      end
      renderer = described_class.new(style: pack, labels: {
        "edition_ordinal" => "{{ var1 | ordinal_word: '', '' }} edition",
      })
      model = bib(<<~X)
        <bibitem type="book">
          <title>A first printing</title>
          <edition>1</edition>
          <date type="published"><on>2000</on></date>
        </bibitem>
      X
      expect(renderer.render(model)).to eq "_A first printing_. first edition."
    end
  end

  describe "identifier kinds" do
    it "renders a typed DOI identifier as a https link" do
      model = bib(<<~X)
        <bibitem type="report">
          <title>Dataset paper</title><date type="published"><on>2020</on></date>
          <docidentifier type="DOI">10.1234/abcd.5678</docidentifier>
        </bibitem>
      X
      expect(described_class.render(model))
        .to include "https://doi.org/10.1234/abcd.5678"
    end

    it "renders a typed MRN identifier verbatim (IALA)" do
      model = bib(<<~X)
        <bibitem type="report">
          <title>VTS Digital Communications</title>
          <date type="published"><on>2026</on></date>
          <docidentifier type="MRN">urn:mrn:iala:pub:g1199:ed1.0</docidentifier>
        </bibitem>
      X
      expect(described_class.render(model))
        .to end_with "2026. urn:mrn:iala:pub:g1199:ed1.0."
    end

    it "excludes internal metanorma docidentifiers" do
      model = bib(<<~X)
        <bibitem type="report">
          <title>Dataset paper</title><date type="published"><on>2020</on></date>
          <docidentifier type="metanorma-ordinal">1</docidentifier>
          <docidentifier type="DOI">10.1234/abcd.5678</docidentifier>
        </bibitem>
      X
      expect(described_class.render(model))
        .to eq "_Dataset paper_. 2020. https://doi.org/10.1234/abcd.5678."
    end
  end

  describe "in-text citation (author-date)" do
    it "takes surname and year" do
      model = bib(<<~X)
        <bibitem type="book">
          <title>X</title><date type="published"><on>2015</on></date>
          <contributor><role type="author"/>
            <person><name><surname>Fowler</surname><forename>H. W</forename></name></person>
          </contributor>
        </bibitem>
      X
      expect(described_class.citation(model)).to eq "FOWLER, 2015"
    end
  end
end
