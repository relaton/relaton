# frozen_string_literal: true

require_relative "../../spec_helper"

# The gem's ISO 690 rendering delegates to relaton-render's instance-driven
# engine; the style instance lives in the relaton-models citation module.
# These specs pin the wiring (the rendering contract itself is pinned by
# relaton-render's ISO 690 conformance suite).
RSpec.describe "BibliographicItem#to_iso690" do
  subject(:item) do
    Relaton::Bib::Bibitem.from_xml(<<~X)
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

  it "renders the reference per the style instance" do
    expect(item.to_iso690)
      .to eq "FARRAR, Frederic William. _Eric, or Little by Little: " \
             "a tale of Roslyn School_. London: Hamilton, 1971."
  end

  it "renders the in-text citation" do
    expect(item.to_iso690_citation).to eq "FARRAR, 1971"
  end

  it "renders a localized reference" do
    model = Relaton::Bib::Bibitem.from_xml(<<~X)
      <bibitem type="book">
        <title>De martyribus</title>
        <date type="published"><on>1994</on></date>
        <contributor><role type="editor"/>
          <person><name><surname>Hamilton</surname><forename>Alastair</forename></name></person>
        </contributor>
        <contributor><role type="publisher"/>
          <organization><name>Amsterdam University Press</name></organization>
        </contributor>
        <place><city>Amsterdam</city></place>
      </bibitem>
    X
    expect(model.to_iso690(lang: "fr"))
      .to eq "HAMILTON, Alastair (éd.). _De martyribus_. Amsterdam : " \
             "Amsterdam University Press, 1994."
  end
end
