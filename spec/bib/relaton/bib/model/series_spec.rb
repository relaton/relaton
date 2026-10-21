describe Relaton::Bib::Series do
  # IETF records carry `<series type="stream">` (the RFC stream, e.g. IETF or
  # IRTF) on 9,828 relaton-data-ietf files — a vocabulary the type enum
  # lacked, which the generated relaton-ts zod schema then enforced and
  # rejected. The fleet-wide series type vocabulary is main, stream, and
  # unset (no data uses "alt", kept for bibdata compatibility).
  context "type vocabulary" do
    it "accepts the IETF stream type and round-trips it" do
      xml = '<bibitem id="r"><title>T</title>' \
            '<series type="stream"><title><content>IETF</content></title></series>' \
            "</bibitem>"
      item = Relaton::Bib::Bibitem.from_xml(xml)
      expect(item.series.first.type).to eq("stream")

      round = Relaton::Bib::Item.from_hash(item.to_h)
      expect(round.series.first.type).to eq("stream")
    end

    it "still accepts main and alt" do
      %w[main alt].each do |t|
        expect(described_class.new(type: t).type).to eq(t)
      end
    end
  end
end
