# The Db cache key of each flavor must be the reference as the flavor's own
# `Bibliography.get` reads it, with the year where that `get` applies it.
RSpec.describe "Relaton::Core::Processor#cache_key" do
  def processor(short)
    Relaton::Db::Registry.instance[short]
  end

  def key(short, ref, year = nil, opts = {})
    processor(short).cache_key(ref, year, opts)
  end

  # The key is the reference parsed by the flavor's pubid class as written:
  # relaton does not rewrite a non-canonical citation (pubid/pubid#463,
  # #464 were closed for this), so such a citation raises.
  context "canonical references only" do
    {
      relaton_w3c: ["W3C xml-names", "https://www.w3.org/TR/xml-names/"],
      relaton_bipm: ["Metrologia 29 6 373", "BIPM Metrologia 29 6 373"],
      relaton_ietf: ["draft-abarth-cake-01", "I-D.draft-abarth-cake-01"],
      relaton_nist: ["NIST SP 800-80(IPD)", "NIST SP 800-80 (IPD)"],
      relaton_jis: ["JIS B 0060 (all parts)", "JIS B 0060 (規格群)"],
    }.each do |short, (canonical, other)|
      it "#{short}: parses #{canonical.inspect}, raises for #{other.inspect}" do
        expect(key(short, canonical)).to be_a Pubid::Identifier
        expect { key(short, other) }.to raise_error Pubid::Errors::ParseError
      end
    end
  end

  context "no key, not cached" do
    it "for a CCSDS format" do
      expect(key(:relaton_ccsds, "CCSDS 720.4-Y-1 (DOC)")).to be_nil
    end

    it "for an Adobe reference the flavor reads as a miss" do
      expect(key(:relaton_adobe, "Adobe Glyph List")).to be_nil
    end

    it "for an incorrect ISBN" do
      expect(key(:relaton_isbn, "ISBN 978-0-580-50101-4")).to be_nil
    end

    it "for IEV, which is not a document identifier" do
      expect(key(:relaton_iec, "IEV")).to be_nil
    end

    it "for an OGC query with a year" do
      expect(key(:relaton_ogc, "OGC 19-025r1", "2010")).to be_nil
    end
  end

  context "the year" do
    it "goes on the adopted document of a CEN adoption" do
      expect(key(:relaton_cen, "CEN ISO/TS 21003-7", "2019").to_hash)
        .to eq key(:relaton_cen, "CEN ISO/TS 21003-7:2019").to_hash
    end

    it "goes on the base document of an ISO supplement, as get does" do
      expect(key(:relaton_iso, "ISO 19115-1/Amd 1", "2018").to_s)
        .to eq "ISO 19115-1:2018/Amd 1"
    end
  end
end
