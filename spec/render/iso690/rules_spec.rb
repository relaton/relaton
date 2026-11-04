# frozen_string_literal: true

require_relative "../spec_helper"
require "tmpdir"
require "relaton/bib"

RSpec.describe Relaton::Render::Iso690::Rules do
  it "resolves a pack's rule selections into the element map" do
    map = described_class.resolve({ "status" => "status_bare" })
    expect(map[:status]).to eq described_class::REGISTRY["status_bare"]
  end

  it "caller elements win over pack selections" do
    override = Class.new
    map = described_class.resolve({ "status" => "status_bare" },
                                  status: override)
    expect(map[:status]).to be override
  end

  it "fails loudly on an unknown rule" do
    expect { described_class.resolve({ "status" => "nonexistent" }) }
      .to raise_error ArgumentError, /unknown citation style rule nonexistent/
  end

  it "the bare status rule cites the stage unparenthesized" do
    model = Relaton::Bib::Item.from_xml(<<~XML)
      <bibitem type="standard" xmlns="http://riboseinc.com/isoxml">
        <title type="main">PAS 9017</title>
        <docidentifier type="BSI">PAS 9017</docidentifier>
        <status><stage>Recommendation</stage></status>
      </bibitem>
    XML
    pack = File.join(Dir.mktmpdir, "status-pack.yml")
    File.write(pack, <<~YML)
      name: bare status pack
      rules:
        status: status_bare
      templates:
        reference: "{{identifier}}. {{status}}."
    YML
    rendered = Relaton::Render::Iso690::Renderer.render(
      model, style: pack, lang: "en",
    )
    expect(rendered).to eq "PAS 9017. Recommendation."
  end

  it "the ieee identifier rule labels DOI and ISBN with a colon" do
    model = Relaton::Bib::Item.from_xml(<<~XML)
      <bibitem type="book">
        <title>A work</title>
        <docidentifier type="DOI">https://doi.org/10.1017/9781108877831</docidentifier>
        <docidentifier type="ISBN">9781108877831</docidentifier>
        <date type="published"><on>2022</on></date>
      </bibitem>
    XML
    pack = File.join(Dir.mktmpdir, "ieee-id-pack.yml")
    File.write(pack, <<~YML)
      name: ieee identifier pack
      rules:
        identifier: ieee_identifier
      templates:
        identifierMode: first
        reference: "{{title}}. {{identifier}}."
    YML
    rendered = Relaton::Render::Iso690::Renderer.render(
      model, style: pack, lang: "en",
    )
    expect(rendered)
      .to eq "_A work_. DOI: https://doi.org/10.1017/9781108877831."
  end

  it "the iho creator rule cites the affiliation after the creator list" do
    model = Relaton::Bib::Item.from_xml(<<~XML)
      <bibitem type="book">
        <title>A joint work</title>
        <date type="published"><on>2019</on></date>
        <contributor><role type="author"/>
          <person><name><surname>Balenson</surname><forename>David</forename></name>
            <affiliation><organization><name>Internet Engineering Task Force</name></organization></affiliation>
          </person>
        </contributor>
        <contributor><role type="publisher"/>
          <organization><name>International Hydrographic Organization</name></organization>
        </contributor>
      </bibitem>
    XML
    pack = File.join(Dir.mktmpdir, "iho-creator-pack.yml")
    File.write(pack, <<~YML)
      name: iho creator pack
      rules:
        creator: iho_creator
      templates:
        reference: "{{creator}}. {{date}}."
    YML
    rendered = Relaton::Render::Iso690::Renderer.render(
      model, style: pack, lang: "en",
    )
    expect(rendered).to include \
        "BALENSON, David, Internet Engineering Task Force"
  end

  it "the iho edition rule cites the raw numeric edition with its own label" do
    model = Relaton::Bib::Item.from_xml(<<~XML)
      <bibitem type="standard">
        <title>Standards for Hydrographic Surveys</title>
        <edition>3.1.0</edition>
        <date type="published"><on>2020</on></date>
        <contributor><role type="publisher"/>
          <organization><name>International Hydrographic Organization</name></organization>
        </contributor>
      </bibitem>
    XML
    pack = File.join(Dir.mktmpdir, "iho-edition-pack.yml")
    File.write(pack, <<~YML)
      name: iho edition pack
      rules:
        edition: iho_edition
      templates:
        reference: "{{title}}. {{edition}}. {{date}}."
    YML
    rendered = Relaton::Render::Iso690::Renderer.render(
      model, style: pack, lang: "en",
    )
    expect(rendered).to eq "_Standards for Hydrographic Surveys_. " \
      "edition 3.1.0. 2020."
  end

  it "the itu identifier rule labels ISBN and ISSN with a colon" do
    model = Relaton::Bib::Item.from_xml(<<~XML)
      <bibitem type="book">
        <title>A handbook</title>
        <docidentifier type="ISBN">92-61-12521-9</docidentifier>
        <date type="published"><on>1998</on></date>
      </bibitem>
    XML
    pack = File.join(Dir.mktmpdir, "itu-id-pack.yml")
    File.write(pack, <<~YML)
      name: itu identifier pack
      rules:
        identifier: itu_identifier
      templates:
        identifierMode: first
        reference: "{{title}}. {{identifier}}."
    YML
    rendered = Relaton::Render::Iso690::Renderer.render(
      model, style: pack, lang: "en",
    )
    expect(rendered).to eq "_A handbook_. ISBN: 92-61-12521-9."
  end

  it "the ieee component part rule cites the host in the IEEE-SA form" do
    model = Relaton::Bib::Item.from_xml(<<~XML)
      <bibitem type="book">
        <title>A chapter</title>
        <date type="published"><on>2005</on></date>
        <contributor><role type="editor"/>
          <person><name><surname>Pellegrini</surname><forename>A. D.</forename></name></person>
        </contributor>
        <relation type="partOf">
          <bibitem type="book">
            <title>The Host Book</title>
            <contributor><role type="editor"/>
              <person><name><surname>Pellegrini</surname><forename>A. D.</forename></name></person>
            </contributor>
            <contributor><role type="editor"/>
              <person><name><surname>Smith</surname><forename>P. K.</forename></name></person>
            </contributor>
            <contributor><role type="publisher"/>
              <organization><name>Academic Press</name></organization>
            </contributor>
            <place><city>London</city></place>
            <date type="published"><on>2005</on></date>
          </bibitem>
        </relation>
      </bibitem>
    XML
    pack = File.join(Dir.mktmpdir, "ieee-cp-pack.yml")
    File.write(pack, <<~YML)
      name: ieee component part pack
      rules:
        component_part: ieee_component_part
      perType:
        - type: component_part
          template: "{{componentpart}}. {{date}}."
      templates:
        titleOpen: "<em>"
        titleClose: "</em>"
        reference: "{{componentpart}}. {{date}}."
    YML
    rendered = Relaton::Render::Iso690::Renderer.render(
      model, style: pack, lang: "en",
    )
    expect(rendered).to include "in Pellegrini, A. D. and P. K. Smith " \
      "(eds.): <em>The Host Book</em>"
  end

  it "the ieee access rule cites the access date bare" do
    model = Relaton::Bib::Item.from_xml(<<~XML)
      <bibitem type="webpage">
        <title>A page</title>
        <uri>https://example.com</uri>
        <date type="accessed"><on>2019-09-03</on></date>
      </bibitem>
    XML
    pack = File.join(Dir.mktmpdir, "ieee-access-pack.yml")
    File.write(pack, <<~YML)
      name: ieee access pack
      rules:
        access: ieee_access
      scheme:
        locale:
          labels:
            viewed: "accessed"
      templates:
        reference: "{{title}}. {{access}}."
    YML
    rendered = Relaton::Render::Iso690::Renderer.render(
      model, style: pack, lang: "en",
    )
    expect(rendered).to eq "_A page_. accessed September 3, 2019."
  end

  it "the ieee medium rule capitalizes the carrier with a trailing comma" do
    model = Relaton::Bib::Item.from_xml(<<~XML)
      <bibitem type="dataset">
        <title>A dataset</title>
        <medium><carrier>dataset</carrier></medium>
        <date type="published"><on>2020</on></date>
      </bibitem>
    XML
    pack = File.join(Dir.mktmpdir, "ieee-medium-pack.yml")
    File.write(pack, <<~YML)
      name: ieee medium pack
      rules:
        medium: ieee_medium
      templates:
        reference: "{{title}}. {{medium}} {{date}}."
    YML
    rendered = Relaton::Render::Iso690::Renderer.render(
      model, style: pack, lang: "en",
    )
    expect(rendered).to eq "_A dataset_. Dataset, 2020."
  end
end
