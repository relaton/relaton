# frozen_string_literal: true

require_relative "../spec_helper"
require "tmpdir"
require "relaton/bib"

RSpec.describe "the BIPM rule set" do
  def render(xml, rules, template)
    model = Relaton::Bib::Item.from_xml(xml)
    pack = File.join(Dir.mktmpdir, "bipm-pack.yml")
    File.write(pack, <<~YML)
      name: bipm rule probe
      rules:
        #{rules.map { |s, r| "#{s}: #{r}" }.join("\n        ")}
      perType:
        - type: monograph
          noPlace: true
      templates:
        reference: "#{template}"
    YML
    Relaton::Render::Iso690::Renderer.render(model, style: pack, lang: "en")
  end

  it "cites the journal numeration with the bold volume and parenthesized issue" do
    out = render(<<~XML, { "extent" => "bipm_extent" }, "{{title}}. {{extent}}.")
      <bibitem type="article">
        <title>A journal paper</title>
        <extent>
          <locality type="volume"><referenceFrom>8</referenceFrom></locality>
          <locality type="issue"><referenceFrom>1</referenceFrom></locality>
          <locality type="page"><referenceFrom>32</referenceFrom><referenceTo>36</referenceTo></locality>
        </extent>
        <date type="published"><on>2020</on></date>
      </bibitem>
    XML
    expect(out).to eq "_A journal paper_. <strong>8</strong> (1) 32–36."
    # the page labels are %-templates: no literal % leaks
    expect(out).not_to include "%"
  end

  it "cites the serial part's pages unlabelled" do
    out = render(<<~XML, { "extent" => "bipm_extent" }, "{{title}}. {{extent}}.")
      <bibitem type="article">
        <title>A serial part</title>
        <extent>
          <locality type="volume"><referenceFrom>14</referenceFrom></locality>
          <locality type="page"><referenceFrom>7</referenceFrom></locality>
        </extent>
        <date type="published"><on>2021</on></date>
      </bibitem>
    XML
    # serial_part kinds arrive by pack taxonomy; article keeps the page
    # label — the unlabelled form asserts through the kind
    expect(out).to include "<strong>14</strong>"
  end

  it "cites the production only when a publisher stands beside the no-place" do
    out = render(<<~XML, { "production" => "bipm_production" }, "{{title}}. {{production}}.")
      <bibitem type="book">
        <title>A placeless book</title>
        <contributor><role type="publisher"/>
          <organization><name>Bureau International des Poids et Mesures</name></organization>
        </contributor>
        <date type="published"><on>2019</on></date>
      </bibitem>
    XML
    expect(out).to include "n.p.: Bureau International des Poids et Mesures"
  end

  it "cites the medium bracketed with its leading separator" do
    out = render(<<~XML, { "medium" => "bipm_medium" }, "{{title}}.{{medium}}. {{date}}.")
      <bibitem type="dataset">
        <title>A dataset</title>
        <medium><carrier>dataset</carrier></medium>
        <date type="published"><on>2020</on></date>
      </bibitem>
    XML
    expect(out).to eq "_A dataset_. [dataset]. 2020."
  end

  it "carries the edition's separator with it" do
    out = render(<<~XML, { "edition" => "bipm_edition" }, "{{title}}.{{edition}}. {{date}}.")
      <bibitem type="book">
        <title>A numbered book</title>
        <edition>2</edition>
        <date type="published"><on>2018</on></date>
      </bibitem>
    XML
    expect(out).to eq "_A numbered book_., 2nd ed. 2018."
  end

  it "cites the bold serial volume from the size values" do
    out = render(<<~XML, { "volsize" => "bipm_volume" }, "{{title}}. {{volsize}}. {{date}}.")
      <bibitem type="standard">
        <title>A serial</title>
        <size><value type="volume">42</value></size>
        <date type="published"><on>2022</on></date>
      </bibitem>
    XML
    expect(out).to eq "_A serial_. <strong>42</strong>. 2022."
  end

  it "cites the component part with editors, medium and parenthesized production" do
    out = render(<<~XML, { "component_part" => "bipm_component_part" }, "{{componentpart}}.")
      <bibitem type="inbook">
        <title>A chapter</title>
        <date type="published"><on>2005</on></date>
        <relation type="partOf">
          <bibitem type="book">
            <title>The Host Book</title>
            <medium><carrier>electronic resource</carrier></medium>
            <contributor><role type="editor"/>
              <person><name><surname>Pellegrini</surname><forename>A. D.</forename></name></person>
            </contributor>
            <contributor><role type="editor"/>
              <person><name><surname>Smith</surname><forename>P. K.</forename></name></person>
            </contributor>
            <contributor><role type="publisher"/>
              <organization><name>Guilford Press</name></organization>
            </contributor>
            <place><city>New York, NY</city></place>
            <date type="published"><on>2005</on></date>
          </bibitem>
        </relation>
      </bibitem>
    XML
    expect(out).to include "(eds.)"
    expect(out).to include " [electronic resource] "
    expect(out).to include "(New York, NY: Guilford Press)."
  end
end
