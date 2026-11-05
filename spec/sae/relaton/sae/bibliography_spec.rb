describe Relaton::Sae::Bibliography do
  # Every example searches the offline `fixtures/index-v2.yaml`, seeded by
  # spec/sae/support/webmock.rb, and reads documents from `fixtures/data/`.
  before do
    stub_request(:get,
                 %r{\A#{Regexp.escape Relaton::Sae::ENDPOINT}data/}o).to_return do |req|
      file = File.join("fixtures", "data", File.basename(req.uri.path))
      if File.exist?(file)
        { status: 200,
          body: File.read(file) }
      else
        { status: 404 }
      end
    end
  end

  def code(ref, year = nil)
    described_class.get(ref, year)&.docidentifier&.first&.content
  end

  context "an undated reference" do
    it "returns the newest edition" do
      expect(code("SAE J3016")).to eq "SAE J3016_202609"
    end

    it "takes the space form SAE writes in its search" do
      expect(code("SAE J 3016")).to eq "SAE J3016_202609"
    end

    it "returns an aerospace revision the reference names" do
      expect(code("SAE AMS4121J")).to eq "SAE AMS4121J"
    end

    # The revision is its own pubid component, so every revision shares the
    # `number` bucket and a reference without one matches them all.
    it "returns the newest revision of an aerospace standard" do
      expect(code("SAE AMS4121")).to eq "SAE AMS4121J"
    end

    it "returns a part, and not the part for its base document" do
      expect(code("SAE J2337/2")).to eq "SAE J2337/2_201702"
      expect(code("SAE J2337")).to be_nil
    end

    it "returns a document whose number ends in letters" do
      expect(code("SAE J1939DA")).to eq "SAE J1939DA_201702"
    end
  end

  context "a dated reference" do
    it "returns the edition of that year" do
      expect(code("SAE J3016:2018")).to eq "SAE J3016_201806"
    end

    it "takes the year as an argument" do
      expect(code("SAE J3016", "2016")).to eq "SAE J3016_201609"
    end

    it "reads SAE's native edition code" do
      expect(code("SAE J3016_202104")).to eq "SAE J3016_202104"
    end

    it "reads the native code in the space form" do
      expect(code("SAE J 3016_202104")).to eq "SAE J3016_202104"
    end

    it "finds nothing for a native code whose month is not published" do
      expect(code("SAE J3016_202101")).to be_nil
    end

    it "returns an aerospace revision by its approval year" do
      expect(code("SAE AMS4121J:2017")).to eq "SAE AMS4121J"
      expect(code("SAE AMS4121:2013")).to eq "SAE AMS4121H"
    end

    it "finds nothing for a year with no edition" do
      expect(code("SAE J3016:2017")).to be_nil
    end
  end

  it "returns a Relaton::Sae::ItemData with the fetch date set" do
    item = described_class.get("SAE J3194")
    expect(item).to be_a Relaton::Sae::ItemData
    expect(item.fetched).to eq Date.today.to_s
    expect(item.docidentifier.map(&:type)).to eq %w[SAE DOI]
  end

  it "accepts a parsed pubid and leaves it as it is" do
    pubid = Pubid::Sae::Identifier.parse("SAE J3016")
    expect(code(pubid, "2021")).to eq "SAE J3016_202104"
    expect(pubid.year).to be_nil
  end

  it "returns nil for a reference pubid cannot read" do
    expect(code("SAE J3016_2021")).to be_nil
    expect(code("SAE CPGM2016")).to be_nil
  end

  it "returns nil for a standard not in the index" do
    expect(code("SAE J9999")).to be_nil
  end

  it "raises Relaton::RequestError when the data repo cannot be reached" do
    stub_request(:get,
                 %r{\A#{Regexp.escape Relaton::Sae::ENDPOINT}}o).to_raise SocketError
    expect { code("SAE J3016") }.to raise_error Relaton::RequestError
  end

  it "raises Relaton::RequestError on a server error" do
    stub_request(:get,
                 %r{\A#{Regexp.escape Relaton::Sae::ENDPOINT}}o).to_return status: 500
    expect { code("SAE J3016") }.to raise_error Relaton::RequestError, /500/
  end
end
