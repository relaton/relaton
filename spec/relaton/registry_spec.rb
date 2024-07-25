RSpec.describe Relaton::Registry do
  before { Relaton.instance_variable_set :@configuration, nil }

  it "outputs backend not present" do
    stub_const "Relaton::Registry::SUPPORTED_GEMS", ["not_supported_gem"]
    expect { Relaton::Registry.clone.instance }.to output(
      /\[relaton\] ERROR: backend not_supported_gem not present/,
    ).to_stderr_from_any_process
  end

  it "finds ISO processor" do
    expect(Relaton::Registry.instance.find_processor("relaton_iso"))
      .to be_instance_of RelatonIso::Processor
  end

  it "returns supported processors" do
    expect(Relaton::Registry.instance.supported_processors).to include :relaton_iso
  end

  context "finds processor by type" do
    it "CN" do
      expect(Relaton::Registry.instance.by_type("CN")).to be_instance_of RelatonGb::Processor
    end

    it "IEC" do
      expect(Relaton::Registry.instance.by_type("IEC")).to be_instance_of RelatonIec::Processor
    end

    it "IETF" do
      expect(Relaton::Registry.instance.by_type("IETF")).to be_instance_of RelatonIetf::Processor
    end

    it "ISO" do
      expect(Relaton::Registry.instance.by_type("ISO")).to be_instance_of RelatonIso::Processor
    end

    it "ITU" do
      expect(Relaton::Registry.instance.by_type("ITU")).to be_instance_of RelatonItu::Processor
    end

    it "NIST" do
      expect(Relaton::Registry.instance.by_type("NIST")).to be_instance_of RelatonNist::Processor
    end

    it "OGC" do
      expect(Relaton::Registry.instance.by_type("OGC")).to be_instance_of RelatonOgc::Processor
    end

    it "CC" do
      expect(Relaton::Registry.instance.by_type("CC")).to be_instance_of RelatonCalconnect::Processor
    end

    it "OMG" do
      expect(Relaton::Registry.instance.by_type("OMG")).to be_instance_of RelatonOmg::Processor
    end

    it "UN" do
      expect(Relaton::Registry.instance.by_type("UN")).to be_instance_of RelatonUn::Processor
    end

    it "W3C" do
      expect(Relaton::Registry.instance.by_type("W3C")).to be_instance_of RelatonW3c::Processor
    end

    it "IEEE" do
      expect(Relaton::Registry.instance.by_type("IEEE")).to be_instance_of RelatonIeee::Processor
    end

    it "IHO" do
      expect(Relaton::Registry.instance.by_type("IHO")).to be_instance_of RelatonIho::Processor
    end

    it "BIPM" do
      expect(Relaton::Registry.instance.by_type("BIPM")).to be_instance_of RelatonBipm::Processor
      expect(Relaton::Registry.instance.processor_by_ref("CCTF")).to be_instance_of RelatonBipm::Processor
    end

    it "ECMA" do
      expect(Relaton::Registry.instance.by_type("ECMA")).to be_instance_of RelatonEcma::Processor
    end

    it "CIE" do
      expect(Relaton::Registry.instance.by_type("CIE")).to be_instance_of RelatonCie::Processor
    end

    it "BSI" do
      expect(Relaton::Registry.instance.by_type("BSI")).to be_instance_of RelatonBsi::Processor
    end

    it "CEN" do
      expect(Relaton::Registry.instance.by_type("CEN")).to be_instance_of RelatonCen::Processor
    end

    it "IANA" do
      expect(Relaton::Registry.instance.by_type("IANA")).to be_instance_of RelatonIana::Processor
    end

    it "3GPP" do
      expect(Relaton::Registry.instance.by_type("3GPP")).to be_instance_of Relaton3gpp::Processor
    end

    it "OASIS" do
      expect(Relaton::Registry.instance.by_type("OASIS")).to be_instance_of RelatonOasis::Processor
    end

    it "DOI" do
      expect(Relaton::Registry.instance.by_type("DOI")).to be_instance_of RelatonDoi::Processor
      expect(Relaton::Registry.instance.processor_by_ref("doi:10.1000/182")).to be_instance_of RelatonDoi::Processor
    end

    it "JIS" do
      expect(Relaton::Registry.instance.by_type("JIS")).to be_instance_of RelatonJis::Processor
    end

    it "XSF" do
      expect(Relaton::Registry.instance.by_type("XEP")).to be_instance_of RelatonXsf::Processor
    end

    it "CCSDS" do
      expect(Relaton::Registry.instance.by_type("CCSDS")).to be_instance_of RelatonCcsds::Processor
    end

    it "ETSI" do
      expect(Relaton::Registry.instance.by_type("ETSI")).to be_instance_of RelatonEtsi::Processor
    end

    it "ISBN" do
      expect(Relaton::Registry.instance.by_type("ISBN")).to be_instance_of RelatonIsbn::Processor
    end

    context "PLATEAU" do
      let(:processor) { Relaton::Registry.instance.by_type("PLATEAU") }
      before { processor }

      it "finds processor" do
        expect(processor).to be_instance_of Relaton::Plateau::Processor
      end

      it "fetch data" do
        expect(Relaton::Plateau::Fetcher).to receive(:fetch).with("plateau-handbooks", output: "dir", format: "xml")
        processor.fetch_data "plateau-handbooks", output: "dir", format: "xml"
      end

      it "from_xml" do
        expect(Relaton::Plateau::XMLParser).to receive(:from_xml).with(:xml).and_return :bibitem
        expect(processor.from_xml(:xml)).to eq :bibitem
      end

      it "hash_to_bib" do
        expect(Relaton::Plateau::HashConverter).to receive(:hash_to_bib).with(:hash).and_return bib: :bib
        expect(Relaton::Plateau::BibItem).to receive(:new).with(bib: :bib).and_return :bibitem
        expect(processor.hash_to_bib(:hash)).to eq :bibitem
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

  it "find processot by dataset" do
    expect(Relaton::Registry.instance.find_processor_by_dataset("nist-tech-pubs"))
      .to be_instance_of RelatonNist::Processor
  end

  it "find processor by dataset" do
    expect(Relaton::Registry.instance.find_processor_by_dataset "etsi-csv").to be_instance_of RelatonEtsi::Processor
  end
end
