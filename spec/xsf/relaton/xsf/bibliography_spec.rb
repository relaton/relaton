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

    # A well-formed id that is not in the index. This used to say "XEP nope",
    # which is not an identifier at all -- it reported "Not found", conflating a
    # malformed reference with an absent document. That conflation is what
    # letting the parse error propagate exists to prevent; see the example
    # below.
    it "not found" do
      expect { Relaton::Xsf::Bibliography.get "XEP 9999" }.to output(
        /\[relaton-xsf\] INFO: \(XEP 9999\) Not found\./,
      ).to_stderr_from_any_process
    end

    it "raises for a malformed reference rather than reporting not found" do
      expect { Relaton::Xsf::Bibliography.get "XEP nope" }
        .to raise_error(Pubid::Errors::ParseError)
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

    # An unrecognized reference RAISES -- like ISO, ETSI and 3GPP, relaton lets
    # it propagate so a caller can tell "malformed identifier" from "no such
    # document". relaton-cli rescues Parslet::ParseFailed and renders
    # "... is not a recognized standards identifier"; Pubid::Errors::ParseError
    # is one, which is what makes that work.
    ["XEP banana", "XEP 00O1", "XEP", "not an identifier"].each do |ref|
      it "raises for #{ref.inspect}" do
        expect { described_class.parse_ref(ref) }
          .to raise_error(Pubid::Errors::ParseError)
      end
    end

    it "raises an error relaton-cli knows how to render" do
      expect { described_class.parse_ref("XEP banana") }
        .to raise_error(Parslet::ParseFailed)
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

    # The parse happens before HitCollection is built, and HitCollection's own
    # rescue relabels StandardError as Relaton::RequestError -- so this also
    # pins that a malformed reference is never reported as a transport failure.
    it "raises for an unparseable reference rather than returning empty" do
      expect { described_class.search("not an identifier") }
        .to raise_error(Pubid::Errors::ParseError)
    end
  end
end
