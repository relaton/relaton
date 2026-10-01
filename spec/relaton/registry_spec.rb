RSpec.describe Relaton::Db::Registry do
  before { Relaton::Db.instance_variable_set :@configuration, nil }

  it "outputs backend not present" do
    stub_const "Relaton::Db::Registry::SUPPORTED_GEMS", ["not_supported_gem"]
    expect { Relaton::Db::Registry.clone.instance }.to output(
      /\[relaton-db\] ERROR: backend not_supported_gem not present/,
    ).to_stderr_from_any_process
  end

  it "finds ISO processor" do
    expect(Relaton::Db::Registry.instance.find_processor("relaton_iso"))
      .to be_instance_of Relaton::Iso::Processor
  end

  # A flavor with a processor that is not in SUPPORTED_GEMS is never
  # registered, so Db#fetch cannot route to it. IALA shipped like that.
  it "lists every flavor processor in SUPPORTED_GEMS" do
    lib = File.expand_path("../../lib", __dir__)
    flavors = Dir[File.join(lib, "relaton/*/processor.rb")].map do |file|
      File.dirname(file).delete_prefix("#{lib}/")
    end
    # relaton/core holds the abstract base processor, not a flavor.
    expect(Relaton::Db::Registry::SUPPORTED_GEMS)
      .to match_array(flavors - ["relaton/core"])
  end

  it "returns supported processors" do
    processors = Relaton::Db::Registry.instance.supported_processors
    expect(processors).to include :relaton_iso
  end

  context "finds processor by type" do
    it "CN" do
      expect(Relaton::Db::Registry.instance.by_type("CN")).to be_instance_of Relaton::Gb::Processor
    end

    it "IEC" do
      expect(Relaton::Db::Registry.instance.by_type("IEC")).to be_instance_of Relaton::Iec::Processor
    end

    it "IETF" do
      expect(Relaton::Db::Registry.instance.by_type("IETF")).to be_instance_of Relaton::Ietf::Processor
    end

    it "ISO" do
      expect(Relaton::Db::Registry.instance.by_type("ISO")).to be_instance_of Relaton::Iso::Processor
    end

    it "ITU" do
      expect(Relaton::Db::Registry.instance.by_type("ITU")).to be_instance_of Relaton::Itu::Processor
    end

    it "NIST" do
      expect(Relaton::Db::Registry.instance.by_type("NIST")).to be_instance_of Relaton::Nist::Processor
    end

    it "OGC" do
      expect(Relaton::Db::Registry.instance.by_type("OGC")).to be_instance_of Relaton::Ogc::Processor
    end

    it "CC" do
      expect(Relaton::Db::Registry.instance.by_type("CC")).to be_instance_of Relaton::Calconnect::Processor
    end

    it "OMG" do
      expect(Relaton::Db::Registry.instance.by_type("OMG")).to be_instance_of Relaton::Omg::Processor
    end

    it "UN" do
      expect(Relaton::Db::Registry.instance.by_type("UN")).to be_instance_of Relaton::Un::Processor
    end

    it "W3C" do
      expect(Relaton::Db::Registry.instance.by_type("W3C")).to be_instance_of Relaton::W3c::Processor
    end

    it "IEEE" do
      expect(Relaton::Db::Registry.instance.by_type("IEEE")).to be_instance_of Relaton::Ieee::Processor
    end

    it "IHO" do
      expect(Relaton::Db::Registry.instance.by_type("IHO")).to be_instance_of Relaton::Iho::Processor
    end

    it "BIPM" do
      expect(Relaton::Db::Registry.instance.by_type("BIPM")).to be_instance_of Relaton::Bipm::Processor
      expect(Relaton::Db::Registry.instance.processor_by_ref("CCTF"))
        .to be_instance_of Relaton::Bipm::Processor
    end

    it "ECMA" do
      expect(Relaton::Db::Registry.instance.by_type("ECMA")).to be_instance_of Relaton::Ecma::Processor
    end

    it "CIE" do
      expect(Relaton::Db::Registry.instance.by_type("CIE")).to be_instance_of Relaton::Cie::Processor
    end

    it "BSI" do
      expect(Relaton::Db::Registry.instance.by_type("BSI")).to be_instance_of Relaton::Bsi::Processor
    end

    it "CEN" do
      expect(Relaton::Db::Registry.instance.by_type("CEN")).to be_instance_of Relaton::Cen::Processor
    end

    it "IANA" do
      expect(Relaton::Db::Registry.instance.by_type("IANA")).to be_instance_of Relaton::Iana::Processor
    end

    it "3GPP" do
      expect(Relaton::Db::Registry.instance.by_type("3GPP")).to be_instance_of Relaton::ThreeGpp::Processor
    end

    it "OASIS" do
      expect(Relaton::Db::Registry.instance.by_type("OASIS")).to be_instance_of Relaton::Oasis::Processor
    end

    it "DOI" do
      expect(Relaton::Db::Registry.instance.by_type("DOI")).to be_instance_of Relaton::Doi::Processor
      expect(Relaton::Db::Registry.instance.processor_by_ref("doi:10.1000/182"))
        .to be_instance_of Relaton::Doi::Processor
    end

    it "JIS" do
      expect(Relaton::Db::Registry.instance.by_type("JIS")).to be_instance_of Relaton::Jis::Processor
    end

    it "XSF" do
      expect(Relaton::Db::Registry.instance.by_type("XEP")).to be_instance_of Relaton::Xsf::Processor
    end

    it "CCSDS" do
      expect(Relaton::Db::Registry.instance.by_type("CCSDS")).to be_instance_of Relaton::Ccsds::Processor
    end

    it "ETSI" do
      expect(Relaton::Db::Registry.instance.by_type("ETSI")).to be_instance_of Relaton::Etsi::Processor
    end

    it "ISBN" do
      expect(Relaton::Db::Registry.instance.by_type("ISBN")).to be_instance_of Relaton::Isbn::Processor
    end

    it "JCGM" do
      expect(Relaton::Db::Registry.instance.by_type("JCGM")).to be_instance_of Relaton::Jcgm::Processor
    end

    it "IALA" do
      expect(Relaton::Db::Registry.instance.by_type("IALA")).to be_instance_of Relaton::Iala::Processor
    end

    context "PLATEAU" do
      let(:processor) { Relaton::Db::Registry.instance.by_type("PLATEAU") }
      before { processor }

      it "finds processor" do
        expect(processor).to be_instance_of Relaton::Plateau::Processor
      end

      it "fetch data" do
        require "relaton/plateau/data_fetcher"
        expect(Relaton::Plateau::DataFetcher).to receive(:fetch)
          .with("plateau-handbooks", output: "dir", format: "xml")
        processor.fetch_data "plateau-handbooks", output: "dir", format: "xml"
      end

      it "from_xml" do
        require "relaton/plateau"
        expect(Relaton::Plateau::Item).to receive(:from_xml)
          .with(:xml).and_return :bibitem
        expect(processor.from_xml(:xml)).to eq :bibitem
      end

      it "grammar_hash" do
        expect(processor.grammar_hash).to be_instance_of String
      end

      it "remove_index_file" do
        index = double "index"
        expect(index).to receive(:remove_file)
        expect(Relaton::Index).to receive(:find_or_create).and_return index
        processor.remove_index_file
      end
    end
  end

  context "processors_by_prefix" do
    let(:registry) { Relaton::Db::Registry.instance }

    it "finds a single processor by exact prefix" do
      expect(registry.processors_by_prefix("NIST").map(&:short)).to eq [:relaton_nist]
    end

    it "finds the JCGM processor by its prefix (no longer BIPM's)" do
      expect(registry.processors_by_prefix("JCGM").map(&:short)).to eq [:relaton_jcgm]
    end

    it "finds a processor by a secondary prefix of the same flavor" do
      expect(registry.processors_by_prefix("NBS").map(&:short)).to eq [:relaton_nist]
    end

    it "finds all processors owning a conflicting prefix, in registration order" do
      expect(registry.processors_by_prefix("ISO/IEC").map(&:short))
        .to eq [:relaton_iec, :relaton_iso]
    end

    it "matches case-insensitively" do
      expect(registry.processors_by_prefix("iso/iec").map(&:short))
        .to eq registry.processors_by_prefix("ISO/IEC").map(&:short)
    end

    it "returns [] for an unknown prefix" do
      expect(registry.processors_by_prefix("BOGUS")).to eq []
    end

    it "routes a pubid-sourced non-obvious prefix (BSI DD)" do
      expect(registry.processors_by_prefix("DD").map(&:short)).to eq [:relaton_bsi]
    end
  end

  it "sources a flavor's #prefixes from pubid (BSI includes DD)" do
    expect(Relaton::Db::Registry.instance.find_processor(:relaton_bsi).prefixes)
      .to include("DD", "BS", "PD")
  end

  it "defaults #prefixes to [prefix] for a flavor with no pubid backing" do
    expect(Relaton::Db::Registry.instance.find_processor(:relaton_un).prefixes)
      .to eq ["UN"]
  end

  # OMG reads its prefixes from Pubid::Omg, which has only its own token.
  it "sources OMG's #prefixes from pubid" do
    processor = Relaton::Db::Registry.instance.find_processor(:relaton_omg)
    expect(processor.instance_variable_get(:@pubid_flavor)).to eq :Omg
    expect(processor.prefixes).to eq ["OMG"]
  end

  it "find processot by dataset" do
    expect(Relaton::Db::Registry.instance.find_processor_by_dataset("nist-tech-pubs"))
      .to be_instance_of Relaton::Nist::Processor
  end

  it "find processor by dataset" do
    expect(Relaton::Db::Registry.instance.find_processor_by_dataset("etsi-csv"))
      .to be_instance_of Relaton::Etsi::Processor
  end

  context "#route (relaton#205)" do
    let(:registry) { described_class.instance }

    # One canonical reference per flavor: the form the flavor's data writes.
    {
      "GB/T 20223-2006" => :relaton_gb,
      "IEC 60050-102:2007" => :relaton_iec,
      "RFC 3986" => :relaton_ietf,
      "ISO 19115-1:2014" => :relaton_iso,
      "ITU-T G.993.5" => :relaton_itu,
      "NIST SP 800-38A" => :relaton_nist,
      "OGC 19-025r1" => :relaton_ogc,
      "CC/DIR 10005" => :relaton_calconnect,
      "OMG AMI4CCM 1.0" => :relaton_omg,
      "UN TRADE/CEFACT/2004/32" => :relaton_un,
      "W3C xml-names" => :relaton_w3c,
      "IEEE 802.11-2016" => :relaton_ieee,
      "IHO S-4" => :relaton_iho,
      "CGPM Resolution (1889)" => :relaton_bipm,
      "Metrologia 29 6 373" => :relaton_bipm,
      "ECMA-6" => :relaton_ecma,
      "CIE 001-1980" => :relaton_cie,
      "BS 8888:2020" => :relaton_bsi,
      "CEN/TS 17267" => :relaton_cen,
      "IANA auto-response-parameters" => :relaton_iana,
      "3GPP TS 23.040" => :relaton_3gpp,
      "OASIS amqp-core" => :relaton_oasis,
      "doi:10.6028/NIST.IR.8245" => :relaton_doi,
      "JIS X 0208" => :relaton_jis,
      "XEP 0001" => :relaton_xsf,
      "CCSDS 230.2-G-1" => :relaton_ccsds,
      "ETSI EN 300 175-1" => :relaton_etsi,
      "ISBN 978-0-306-40615-7" => :relaton_isbn,
      "PLATEAU Handbook #00 1.0" => :relaton_plateau,
      "OIML R 138" => :relaton_oiml,
      "JCGM 100:2008" => :relaton_jcgm,
      "ПМГ 03-2025" => :relaton_easc,
      "GOST R 34.12-2015" => :relaton_gost,
      "Adobe TN 5014" => :relaton_adobe,
      "IALA S1070" => :relaton_iala,
      "draft-abarth-cake-01" => :relaton_ietf,
    }.each do |ref, short|
      it "routes #{ref.inspect} to #{short}" do
        expect(registry.route(ref).first).to be short
      end
    end

    it "hands over the parsed pubid of an exact parse" do
      stdclass, pubid = registry.route "ISO 19115-1:2014"
      expect(stdclass).to be :relaton_iso
      expect(pubid).to be_a Pubid::Iso::Identifier
      expect(pubid.to_s).to eq "ISO 19115-1:2014"
    end

    context "a co-published identifier: the printed form decides" do
      {
        "ISO/IEC 27001:2022" => :relaton_iso,
        "ISO/IEC/IEEE 8802-3:2021" => :relaton_iso,
        "IEC/ISO 27001:2022" => :relaton_iec,
      }.each do |ref, short|
        it "routes #{ref.inspect} to #{short}" do
          expect(registry.route(ref).first).to be short
        end
      end

      it "drops a parse by another co-publisher's flavor" do
        expect(registry.route("ISO/IEC 27001:2022").last).to be_nil
      end
    end

    context "a partial parse by another flavor does not route" do
      {
        "ATN5014" => :relaton_adobe,
        "CCTF" => :relaton_bipm,
        "ISO REF" => :relaton_iso,
        "DD 240" => :relaton_bsi,
      }.each do |ref, short|
        it "routes #{ref.inspect} to #{short}" do
          expect(registry.route(ref).first).to be short
        end
      end
    end

    [
      "978-0-306-40615-7", # a bare ISBN: IEC reads it as `IEC 978-...`
      "10.6028/NIST.IR.8245", # a bare DOI: Pubid::Un parses it exactly
      "TRADE/CEFACT/2004/32", # a UN symbol without the UN token
      "ABC 123456",
    ].each do |ref|
      it "raises for #{ref.inspect}, which no flavor recognizes" do
        expect { registry.route(ref) }
          .to raise_error Relaton::UnknownReferenceError, /#{Regexp.escape ref}/
      end
    end

    context "a flavor whose identifiers print no publisher token" do
      {
        "19-025r1" => :relaton_ogc,
        "TS 23.207:REL-18/18.0.0" => :relaton_3gpp,
        "TR 00.01U:UMTS/3.0.0" => :relaton_3gpp,
      }.each do |ref, short|
        it "routes the bare #{ref.inspect} to #{short}" do
          expect(registry.route(ref).first).to be short
        end
      end
    end

    it "raises for a URN no flavor owns, not ArgumentError" do
      expect { registry.route("urn:foo:bar") }
        .to raise_error Relaton::UnknownReferenceError
    end

    it "keeps the prefix fallback for a combined reference" do
      expect(registry.route("ISO 19115-1, Amd 1")).to eq [:relaton_iso, nil]
    end

    it "does not depend on the registration order" do
      refs = ["ISO/IEC 27001:2022", "IEC 60050-102:2007", "ATN5014",
              "doi:10.6028/NIST.IR.8245", "BS 8888:2020", "OGC 19-025r1"]
      expected = refs.map { |ref| registry.route(ref).first }
      original = registry.processors
      registry.instance_variable_set :@processors, original.to_a.reverse.to_h
      expect(refs.map { |ref| registry.route(ref).first }).to eq expected
    ensure
      registry.instance_variable_set :@processors, original
    end
  end
end
