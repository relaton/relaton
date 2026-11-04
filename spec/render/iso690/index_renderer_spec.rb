# frozen_string_literal: true

require_relative "../spec_helper"
require "relaton/bib"

RSpec.describe Relaton::Render::Iso690::IndexRenderer do
  def bib(xml)
    Relaton::Bib::Bibitem.from_xml(xml)
  end

  let(:farrar) do
    bib(<<~X)
      <bibitem type="book">
        <title>Eric, or Little by Little</title>
        <date type="published"><on>1971</on></date>
        <contributor><role type="author"/>
          <person><name><surname>Farrar</surname><forename>Frederic</forename></name></person>
        </contributor>
      </bibitem>
    X
  end

  let(:hamilton) do
    bib(<<~X)
      <bibitem type="book">
        <title>From martyr to muppy</title>
        <date type="published"><on>1994</on></date>
        <contributor><role type="author"/>
          <person><name><surname>Hamilton</surname><forename>Alastair</forename></name></person>
        </contributor>
      </bibitem>
    X
  end

  let(:iso_body) do
    bib(<<~X)
      <bibitem type="book">
        <title>ISO 690:2010</title>
        <contributor><role type="author"/>
          <organization><name>International Organization for Standardization</name></organization>
        </contributor>
      </bibitem>
    X
  end

  it "sorts references by the style's sortKey (creator, then date)" do
    refs = described_class.new.references([hamilton, iso_body, farrar])
    expect(refs).to eq [
      "FARRAR, Frederic. _Eric, or Little by Little_. 1971.",
      "HAMILTON, Alastair. _From martyr to muppy_. 1994.",
      "INTERNATIONAL ORGANIZATION FOR STANDARDIZATION. _ISO 690:2010_.",
    ]
  end

  it "numbers the laid-out index by default" do
    refs = described_class.new.render([hamilton, farrar])
    expect(refs.first).to start_with "1. FARRAR"
    expect(refs.last).to start_with "2. HAMILTON"
  end

  it "renders bare references when numbering is none" do
    refs = described_class.new.render([farrar], numbering: "none")
    expect(refs).to eq ["FARRAR, Frederic. _Eric, or Little by Little_. 1971."]
  end

  it "sorts ties on the first key by the second key (date)" do
    later = bib(<<~X)
      <bibitem type="book">
        <title>Same author, later</title>
        <date type="published"><on>2020</on></date>
        <contributor><role type="author"/>
          <person><name><surname>Farrar</surname><forename>Frederic</forename></name></person>
        </contributor>
      </bibitem>
    X
    refs = described_class.new.references([later, farrar])
    expect(refs.first).to include "1971"
    expect(refs.last).to include "2020"
  end
end
