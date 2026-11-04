# frozen_string_literal: true

require_relative "../spec_helper"
require "tmpdir"
require "relaton/bib"

RSpec.describe "the JIS rule set" do
  def render(xml, rules, template)
    model = Relaton::Bib::Item.from_xml(xml)
    pack = File.join(Dir.mktmpdir, "jis-pack.yml")
    File.write(pack, <<~YML)
      name: jis rule probe
      rules:
        #{rules.map { |s, r| "#{s}: #{r}" }.join("\\n        ")}
      templates:
        reference: "#{template}"
    YML
    Relaton::Render::Iso690::Renderer.render(model, style: pack, lang: "en")
  end

  it "cites the host title first, then the host creator, closing the paren" do
    out = render(<<~XML, { "component_part" => "jis_component_part" }, "{{componentpart}}")
      <bibitem type="inbook">
        <title>A chapter</title>
        <date type="published"><on>1996</on></date>
        <relation type="partOf">
          <bibitem type="book">
            <title>Collected Essays</title>
            <contributor><role type="author"/>
              <organization><name>UNICEF</name></organization>
            </contributor>
          </bibitem>
        </relation>
      </bibitem>
    XML
    expect(out).to eq "Collected Essays UNICEF)"
  end

  it "falls back to the host's series when the part carries none" do
    out = render(<<~XML, { "series" => "jis_series" }, "{{title}}. {{series}}.")
      <bibitem type="inbook">
        <title>A chapter</title>
        <date type="published"><on>2020</on></date>
        <relation type="partOf">
          <bibitem type="book">
            <title>The Host Book</title>
            <series><title>Host Series</title></series>
          </bibitem>
        </relation>
      </bibitem>
    XML
    expect(out).to eq "_A chapter_. _Host Series_."
  end

  it "keeps the last locality per type in the book-family extent" do
    out = render(<<~XML, { "extent" => "jis_extent" }, "{{title}}. {{extent}}.")
      <bibitem type="book">
        <title>A repeated book</title>
        <extent>
          <locality type="page"><referenceFrom>1</referenceFrom></locality>
          <locality type="volume"><referenceFrom>3</referenceFrom></locality>
          <locality type="page"><referenceFrom>19</referenceFrom></locality>
        </extent>
        <date type="published"><on>2020</on></date>
      </bibitem>
    XML
    expect(out).to eq "_A repeated book_. vol. 3 p. 19."
  end
end
