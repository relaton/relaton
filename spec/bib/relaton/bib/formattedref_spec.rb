# frozen_string_literal: true

require "spec_helper"

# relaton-bib#94: the bibdata grammar has no `format` attribute on
# <formattedref> — an ingested format= is dropped and never re-emitted.
RSpec.describe "Bib::Formattedref serialization" do
  it "does not emit the format attribute" do
    item = Relaton::Bib::Bibitem.from_xml(<<~XML)
      <bibitem id="C" type="standard">
        <title type="main">T3</title>
        <docidentifier>C 3</docidentifier>
        <formattedref format="text/plain">C 3 past</formattedref>
      </bibitem>
    XML
    xml = item.to_xml
    expect(xml).not_to include("formattedref format=")
    expect(xml).to include("<formattedref>C 3 past</formattedref>")
  end
end
