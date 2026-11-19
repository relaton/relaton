describe Relaton::Arxiv::Bibliography do
  let(:endpoint) { Relaton::Arxiv::Api::ENDPOINT }

  context "from the arXiv API" do
    it "fetches a versioned id", vcr: "versioned" do
      item = described_class.get "arXiv:2301.00001v1"
      expect(item).to be_instance_of Relaton::Bib::ItemData
      expect(item.docidentifier.first.content).to eq "arXiv:2301.00001v1"
      expect(item.title.first.content).to eq "NFTrig"
    end

    it "fetches the latest version of an unversioned id", vcr: "unversioned" do
      item = described_class.get "arXiv:1706.03762"
      expect(item.docidentifier.first.content).to eq "arXiv:1706.03762v7"
    end

    it "fetches an old-style id in lower case", vcr: "old_style" do
      item = described_class.get "arxiv:hep-th/9901001"
      expect(item.docidentifier.first.content).to eq "arXiv:hep-th/9901001v3"
    end
  end

  context "with a stubbed API" do
    def stub_feed(id, body: nil, status: 200)
      stub_request(:get, endpoint).with(query: { "id_list" => id })
        .to_return(status: status, body: body || File.read("fixtures/not-found.xml"))
    end

    it "takes a parsed pubid and does not mutate it" do
      stub_feed "hep-th/9901001", body: File.read("fixtures/hep-th-9901001.xml")
      pubid = Pubid::Arxiv.parse "arXiv:hep-th/9901001"
      before = pubid.to_hash
      item = described_class.get pubid
      expect(item.docidentifier.first.content).to eq "arXiv:hep-th/9901001v3"
      expect(pubid.to_hash).to eq before
    end

    it "answers nil for an id arXiv does not have" do
      stub_feed "2301.99999"
      expect(described_class.get("arXiv:2301.99999")).to be_nil
    end

    it "answers nil for a reference that is not an arXiv id" do
      expect(described_class.get("arXiv:not-an-id")).to be_nil
    end

    it "raises RequestError on a server error" do
      stub_feed "2301.00001", status: 500, body: "oops"
      expect { described_class.get "arXiv:2301.00001" }
        .to raise_error Relaton::RequestError
    end

    it "answers nil for an id arXiv rejects" do
      stub_feed "foo/9901001", body: File.read("fixtures/error-entry.xml")
      expect(described_class.get("arXiv:foo/9901001")).to be_nil
    end

    it "raises RequestError on a network error" do
      stub_request(:get, endpoint).with(query: hash_including({})).to_timeout
      expect { described_class.get "arXiv:2301.00001" }
        .to raise_error Relaton::RequestError
    end

    it "raises RequestError on a system call error" do
      stub_request(:get, endpoint).with(query: hash_including({}))
        .to_raise(Errno::ETIMEDOUT)
      expect { described_class.get "arXiv:2301.00001" }
        .to raise_error Relaton::RequestError
    end
  end
end
