describe Relaton::Bib::Note do
  # relaton-bib#122: a biblionote must preserve an inline <link> (target URL)
  # across a from_xml -> to_xml round-trip, the same way <em>/<strong> already do.
  # Regression from the issue's exact reproduction (metanorma-pdfa#53).
  context "inline <link> round-trip (#122)" do
    let(:input_xml) do
      '<bibitem id="x"><title>T</title>' \
        '<note type="display">a <link target="https://x.org">L</link> b</note>' \
        "</bibitem>"
    end

    let(:output_xml) { Relaton::Bib::Bibitem.to_xml(Relaton::Bib::Bibitem.from_xml(input_xml)) }

    it "keeps the <link> element and its target attribute" do
      expect(output_xml).to include('<link target="https://x.org">L</link>')
    end

    it "does not collapse the link to bare text" do
      expect(output_xml).not_to match(%r{<note[^>]*>a L b</note>})
    end

    it "still round-trips the surrounding text and sibling markup" do
      xml = '<bibitem id="x"><title>T</title>' \
             '<note type="display">a <em>e</em> <link target="https://x.org">L</link> b</note>' \
             "</bibitem>"
      out = Relaton::Bib::Bibitem.to_xml(Relaton::Bib::Bibitem.from_xml(xml))
      expect(out).to include('a <em>e</em> <link target="https://x.org">L</link> b')
    end
  end
end
