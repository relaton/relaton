require "spec_helper"
require "json"

module Relaton
  module Bib
    RSpec.describe "export formats parity" do
      let(:xml) do
        <<~XML
          <bibitem type="standard">
            <title type="title-intro" language="eng">Quality management systems</title>
            <title type="title-main" language="eng">Requirements</title>
            <docidentifier type="ISO" primary="true">ISO 9001:2026</docidentifier>
            <date type="published"><on>2026</on></date>
            <contributor>
              <role type="publisher"/>
              <organization><name>ISO</name></organization>
            </contributor>
          </bibitem>
        XML
      end

      let(:item) { Relaton::Bib::Item.from_xml(xml) }

      it "renders ISO 690: identifier, composed title, publisher, year" do
        expect(item.to_iso690).to eq(
          "ISO 9001:2026, Quality management systems — Requirements. ISO, 2026."
        )
      end

      it "renders Chicago author-date for a standard" do
        expect(item.to_chicago).to eq(
          "ISO. 2026. ISO 9001:2026. Quality management systems — Requirements."
        )
      end

      it "renders APA 7th for a standard" do
        expect(item.to_apa).to eq(
          "ISO. (2026). Quality management systems — Requirements (ISO 9001:2026)."
        )
      end

      it "renders RIS with composed title and identifier" do
        lines = item.to_ris.lines.map(&:chomp)
        expect(lines.first).to eq("TY  - STD")
        expect(lines).to include("TI  - Quality management systems — Requirements")
        expect(lines).to include("ID  - ISO 9001:2026")
        expect(lines).to include("PY  - 2026")
        expect(lines.last).to eq("ER  - ")
      end

      it "renders CSL-JSON array" do
        arr = JSON.parse(item.to_csl_json)
        expect(arr.length).to eq(1)
        expect(arr.first["id"]).to eq("ISO 9001:2026")
        expect(arr.first["type"]).to eq("standard")
        expect(arr.first["issued"]).to eq({ "date-parts" => [["2026"]] })
        expect(arr.first["publisher"]).to eq("ISO")
      end

      it "renders person authors in citation name forms" do
        book_xml = <<~XML
          <bibitem type="book">
            <title>The History of GEBCO</title>
            <docidentifier type="IHO" primary="true">B-10</docidentifier>
            <date type="published"><on>2003</on></date>
            <contributor>
              <role type="author"/>
              <person><name><forename>Jane</forename><surname>Austen</surname></name></person>
            </contributor>
            <contributor>
              <role type="publisher"/>
              <organization><name>IHO</name></organization>
            </contributor>
          </bibitem>
        XML
        book = Relaton::Bib::Item.from_xml(book_xml)
        expect(book.to_iso690).to include("Austen, J.")
        expect(book.to_ris).to include("AU  - Austen, Jane")
        expect(JSON.parse(book.to_csl_json).first["author"])
          .to include({ "family" => "Austen", "given" => "Jane" })
      end
    end
  end
end
