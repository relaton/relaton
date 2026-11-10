# frozen_string_literal: true

require "spec_helper"

# The slug form (relaton#441): Docidentifier#to_s(form: :slug) renders
# the pubid-scheme URN in HTTP-path clothes; Pubid.from_slug parses it
# back to the same identifier. Flavors whose pubid-scheme schema has
# not landed yet degrade to the stored content.
RSpec.describe Relaton::Bib::Docidentifier do
  it "renders and parses the slug for a landed flavor" do
    require "pubid"
    docid = described_class.new(type: "NIST", content: "NIST SP 800-53r5")

    slug = docid.to_s(form: :slug)
    expect(slug).to eq("nist/sp/800-53/pub-NIST/series-SP/subseries-800/edtype-r/ed-5")

    back = ::Pubid.from_slug(slug)
    expect(back.to_hash).to eq(::Pubid::Nist.parse("NIST SP 800-53r5").to_hash)
  end

  it "keeps to_s without a form on the stored content" do
    docid = described_class.new(type: "NIST", content: "NIST SP 800-53r5")
    expect(docid.to_s).to eq("NIST SP 800-53r5")
  end

  it "raises on an unknown form" do
    docid = described_class.new(type: "NIST", content: "NIST SP 800-53r5")
    expect { docid.to_s(form: :nonsense) }.to raise_error(ArgumentError)
  end

  it "degrades to content for a flavor without a landed schema" do
    docid = described_class.new(type: "CSA", content: "CSA C22.2 NO. 125-M84 (R2004)")
    expect(docid.to_s(form: :slug)).to eq("CSA C22.2 NO. 125-M84 (R2004)")
  end

  # Every SLUG_PUBID row, verified end-to-end at adoption (relaton#441):
  # parse the stored content as the row's flavor, slug it, parse the slug
  # back, and require the same identifier. The corpus doubles as the
  # canary for the pubid URN schemas: a schema regression fails here
  # before any consumer sees it.
  describe "SLUG_PUBID round-trips every landed flavor" do
    # type => [pubid flavor, a docidentifier content the flavor stores]
    CORPUS = {
      "ISO" => [:Iso, "ISO 123:1994"],
      "IEC" => [:Iec, "IEC 61058-2-4:1995"],
      "IEEE" => [:Ieee, "IEEE P802.5t/D-2.5"],
      "IHO" => [:Iho, "S-129"],
      "ITU-T" => [:Itu, "ITU-T H.222.0"],
      "ITU-R" => [:Itu, "ITU-R BO.600-1"],
      "ITU" => [:Itu, "ITU-T A.1"],
      "W3C" => [:W3c, "W3C CR-json-ld11-20200316"],
      "3GPP" => [:Tgpp, "3GPP TR 21.905"],
      "OGC" => [:Ogc, "OGC 19-025r1"],
      "OASIS" => [:Oasis, "OASIS amqp-core"],
      "OMG" => [:Omg, "OMG NEG 1.0"],
      "UN" => [:Un, "TRADE/CEFACT/2004/32"],
      "XEP" => [:Xsf, "XEP 0001"],
      "EVS" => [:Evs, "EVS-EN 18216:2026"],
      "CCSDS" => [:Ccsds, "CCSDS 123.0-B-1"],
      "CEN" => [:CenCenelec, "CEN ISO/TS 21003-7:2019"],
      "BIPM" => [:Bipm, "CGPM RES (1889)"],
      "CalConnect" => [:Calconnect, "CC/DIR 10005:2019"],
      "ECMA" => [:Ecma, "ECMA-6"],
      "GB" => [:Gb, "GB/T 13368"],
      "IANA" => [:Iana, "IANA auto-response-parameters"],
      "NIST" => [:Nist, "NIST SP 800-53r5"],
      "BSI" => [:Bsi, "BSI PAS 2031:2019"],
      "IETF" => [:Ietf, "RFC 8446"],
      "Internet-Draft" => [:Ietf, "draft-ietf-quic-http-34"],
      "GOST" => [:Gost, "GOST R 7.0.100-2018"],
      "JCGM" => [:Jcgm, "JCGM 100:2008"],
      "OIML" => [:Oiml, "OIML R 111-1:2004"],
      "SAE" => [:Sae, "SAE J3016_202104"],
      "IALA" => [:Iala, "IALA G1111"],
      "EASC" => [:Easc, "ПМГ 02-2008"],
      "DOI" => [:Doi, "10.5072/zenodo.1234"],
      "ISBN" => [:Isbn, "ISBN 978-3-16-148410-0"],
      "JIS" => [:Jis, "JIS Z 8301:2019"],
    }.freeze

    CORPUS.each do |type, (flavor, content)|
      it "#{type}: #{content}" do
        require "pubid"
        docid = described_class.new(type: type, content: content)
        slug = docid.to_s(form: :slug)

        expect(slug).not_to eq(content) # it really rendered the slug form
        parsed = ::Pubid.const_get(flavor).parse(content)
        expect(::Pubid.from_slug(slug).to_hash).to eq(parsed.to_hash)
      end
    end

    it "keeps the publisher forms gated on FORM_PUBID (relaton#49)" do
      # ISO is not in FORM_PUBID: its external/internal forms stay the
      # stored content even though it now emits slugs.
      docid = described_class.new(type: "ISO", content: "ISO 123:1994")
      expect(docid.to_s(form: :external)).to eq("ISO 123:1994")
      expect(docid.to_s(form: :internal)).to eq("ISO 123:1994")
    end
  end
end
