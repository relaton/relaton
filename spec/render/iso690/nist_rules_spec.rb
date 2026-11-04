# frozen_string_literal: true

require_relative "../spec_helper"
require "tmpdir"
require "relaton/bib"

RSpec.describe "the NIST rule set" do
  def render(xml, rules, template)
    model = Relaton::Bib::Item.from_xml(xml)
    pack = File.join(Dir.mktmpdir, "nist-pack.yml")
    File.write(pack, <<~YML)
      name: nist rule probe
      rules:
        #{rules.map { |s, r| "#{s}: #{r}" }.join("\n        ")}
      templates:
        reference: "#{template}"
    YML
    Relaton::Render::Iso690::Renderer.render(model, style: pack, lang: "en")
  end

  it "cites the FIPS series' corporate creator" do
    out = render(<<~XML, { "creator" => "nist_creator" }, "{{creator}}.")
      <bibitem type="standard">
        <title>Personal Identity Verification</title>
        <series><title>NIST Federal Information Processing Standards</title><number>201-3</number></series>
        <contributor><role type="publisher"/>
          <organization><name>National Institute of Standards and Technology</name></organization>
        </contributor>
        <date type="published"><on>2022</on></date>
      </bibitem>
    XML
    expect(out).to eq "National Institute of Standards and Technology."
  end

  it "falls back to the publisher name for creatorless standards" do
    out = render(<<~XML, { "creator" => "nist_creator" }, "{{creator}}.")
      <bibitem type="standard">
        <title>Guide to Bluetooth security</title>
        <docidentifier type="NIST SP">NIST SP 800-121 Rev. 2</docidentifier>
        <contributor><role type="publisher"/>
          <organization><name>National Institute of Standards and Technology</name></organization>
        </contributor>
        <date type="published"><on>2012</on></date>
      </bibitem>
    XML
    expect(out).to eq "National Institute of Standards and Technology."
  end

  it "renders the NIST draft form with the worded iteration" do
    out = render(<<~XML, { "draft" => "nist_draft" }, "{{draft}}.")
      <bibitem type="standard">
        <title>A draft document</title>
        <docidentifier type="NIST SP">NIST SP 800-100</docidentifier>
        <status><stage>draft-public</stage><iteration>3</iteration></status>
        <contributor><role type="publisher"/>
          <organization><name>National Institute of Standards and Technology</name></organization>
        </contributor>
        <date type="published"><on>2020</on></date>
      </bibitem>
    XML
    expect(out).to eq "Draft (Third Public Draft)."
  end

  it "renders the series with abbreviation, part number and revision" do
    out = render(<<~XML, { "series" => "nist_series" }, "{{series}}.")
      <bibitem type="standard">
        <title>Guide to IPsec VPNs</title>
        <series><title>NIST Special Publication</title><abbreviation>NIST SP</abbreviation><number>800-77</number><partnumber>1</partnumber></series>
        <edition>Revision 1</edition>
        <contributor><role type="publisher"/>
          <organization><name>National Institute of Standards and Technology</name></organization>
        </contributor>
        <date type="published"><on>2020</on></date>
      </bibitem>
    XML
    expect(out).to eq "NIST Special Publication (SP) 800-77.1 Rev. 1."
  end

  # The nist-long derivation path is preserved verbatim (minus a
  # sigla-strip fix); every NIST fixture carries a series element, so
  # it has no exercised contract to assert against.

  it "orders authoritative identifiers before the kind group, labels ISBN" do
    out = render(<<~XML, { "identifier" => "nist_identifier" }, "{{identifier}}.")
      <bibitem type="book">
        <title>A joint work</title>
        <docidentifier type="ISO">ISO 690:2021</docidentifier>
        <docidentifier type="ISBN">978-1-56619-909-4</docidentifier>
        <docidentifier type="DOI">10.1000/xyz123</docidentifier>
        <date type="published"><on>2021</on></date>
      </bibitem>
    XML
    expect(out).to eq "ISO 690:2021. ISBN: 978-1-56619-909-4. " \
      "https://doi.org/10.1000/xyz123."
  end

  it "cites the parenthesized publisher block for NIST series" do
    out = render(<<~XML, { "nistpublisher" => "nist_publisher" }, "{{title}}{{nistpublisher}}.")
      <bibitem type="standard">
        <title>Guide to Malware Incident Prevention</title>
        <series><title>NIST Special Publication</title><number>800-83</number></series>
        <contributor><role type="publisher"/>
          <organization><name>National Institute of Standards and Technology</name></organization>
        </contributor>
        <date type="published"><on>2013</on></date>
      </bibitem>
    XML
    expect(out).to eq "_Guide to Malware Incident Prevention_ " \
      "(National Institute of Standards and Technology, Gaithersburg, MD)."
  end

  it "cites the component part with host editors, production and host date" do
    out = render(<<~XML, { "component_part" => "nist_component_part" }, "{{componentpart}}.")
      <bibitem type="inbook">
        <title>Gross and fine motor play</title>
        <date type="published"><on>2005</on></date>
        <relation type="partOf">
          <bibitem type="book">
            <title>The nature of play</title>
            <contributor><role type="editor"/>
              <person><name><surname>Pellegrini</surname><forename>Anthony</forename></name></person>
            </contributor>
            <contributor><role type="editor"/>
              <person><name><surname>Smith</surname><forename>Peter</forename></name></person>
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
    expect(out).to start_with "In: Pellegrini Anthony and Smith Peter (eds.)"
    expect(out).to include "(New York, NY: Guilford Press), 2005."
  end

  it "falls back to the host's date when the part carries none" do
    out = render(<<~XML, { "date" => "nist_date" }, "{{title}}. {{date}}.")
      <bibitem type="inbook">
        <title>A dateless chapter</title>
        <relation type="partOf">
          <bibitem type="book">
            <title>The Host Book</title>
            <date type="published"><on>2018</on></date>
          </bibitem>
        </relation>
      </bibitem>
    XML
    expect(out).to eq "_A dateless chapter_. 2018."
  end
end
