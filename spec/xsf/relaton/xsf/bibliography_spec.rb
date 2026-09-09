describe Relaton::Xsf::Bibliography do
  context "get" do
    it "successful", vcr: "get_successful" do
      expect do
        file = "fixtures/bibdata.xml"
        bib = Relaton::Xsf::Bibliography.get "XEP 0001"
        xml = bib.to_xml bibdata: true
        File.write file, xml, encoding: "UTF-8" unless File.exist? file
        expect(bib).to be_instance_of Relaton::Xsf::ItemData
        expect(bib.docidentifier.first.content).to eq "XEP 0001"
        expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8").gsub(
          /(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s
        )
      end.to output(
        include("[relaton-xsf] INFO: (XEP 0001) Fetching from Relaton repository ...",
                "[relaton-xsf] INFO: (XEP 0001) Found: `XEP 0001`"),
      ).to_stderr_from_any_process
    end

    it "not found", vcr: "get_not_found" do
      expect { Relaton::Xsf::Bibliography.get "XEP nope" }.to output(
        /\[relaton-xsf\] INFO: \(XEP nope\) Not found\./,
      ).to_stderr_from_any_process
    end
  end
  # Reference parsing lives here, not in HitCollection: `Index::Type` narrows
  # only when its search argument is not a String, so the entry point is where
  # the string has to become an identifier.
  describe ".parse_ref" do
    {
      "XEP 0001" => "XEP 0001",   # canonical
      "XEP-0001" => "XEP 0001",   # the spelling xmpp.org itself uses
      "0001" => "XEP 0001",       # bare -- the old substring match resolved it
      "xep 0001" => "XEP 0001",   # token match is case-insensitive
      "  XEP 0001  " => "XEP 0001",
      "XEP README" => "XEP README",
    }.each do |ref, rendered|
      it "parses #{ref.inspect}" do
        expect(described_class.parse_ref(ref).to_s).to eq rendered
      end
    end

    # Strictness is the point: it is what keeps a typo a warning rather than a
    # silent miss. pubid takes README and xxxx as literal numbers, nothing else.
    ["XEP banana", "XEP 00O1", "XEP", "not an identifier"].each do |ref|
      it "rejects #{ref.inspect}" do
        expect(Relaton.logger_pool).to receive(:warn).with(/Failed to parse pubid/, any_args)
        expect(described_class.parse_ref(ref)).to be_nil
      end
    end
  end

  describe ".search" do
    def files(ref)
      described_class.search(ref).map { |hit| hit.hit[:url].split("/").last }
    end

    it "resolves every accepted spelling to the same document" do
      %w[XEP\ 0001 XEP-0001 0001 xep\ 0001].each do |ref|
        expect(files(ref)).to eq ["xep-0001.yaml"]
      end
    end

    it "resolves the two rows that are pages rather than XEPs" do
      expect(files("XEP README")).to eq ["xep-readme.yaml"]
      expect(files("XEP xxxx")).to eq ["xep-xxxx.yaml"]
    end

    # The old substring match answered this with 11 documents, and `get` took
    # `.first`.
    it "does not answer a truncated number with every document containing it" do
      expect(files("001")).to be_empty
    end

    it "returns an empty collection for an unparseable reference" do
      expect(Relaton.logger_pool).to receive(:warn).with(/Failed to parse pubid/, any_args)
      expect(described_class.search("not an identifier")).to be_empty
    end
  end
end
