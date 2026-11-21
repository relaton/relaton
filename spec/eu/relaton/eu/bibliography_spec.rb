describe Relaton::Eu::Bibliography do
  # Every example searches the offline `fixtures/index-v2.yaml`, seeded by
  # spec/eu/support/webmock.rb, and reads documents from `fixtures/data/`.
  # Both are the output of `DataFetcher` over `fixtures/cellar/`.
  before do
    stub_request(:get, %r{\A#{Regexp.escape Relaton::Eu::ENDPOINT}data/}o).to_return do |req|
      file = File.join("fixtures", "data", File.basename(req.uri.path))
      File.exist?(file) ? { status: 200, body: File.read(file) } : { status: 404 }
    end
  end

  def code(ref, year = nil)
    described_class.get(ref, year)&.docidentifier&.first&.content
  end

  it "returns a pre-2015 regulation" do
    expect(code("EU Regulation 1227/2011")).to eq "EU Regulation 1227/2011"
  end

  it "returns a regulation from 2015" do
    expect(code("EU Regulation 2016/679")).to eq "EU Regulation 2016/679"
  end

  # Its index row carries `subtype: impl`; the reference names no subtype.
  it "returns an implementing regulation" do
    expect(code("EU Regulation 2016/1356")).to eq "EU Regulation 2016/1356"
  end

  # An act with no English version. Its pair reads as a later act's
  # <year>/<number>, so pubid prints `No` to mark <number>/<year>: without
  # it, `EU Regulation 2015/1968` is regulation 1968 of 2015.
  it "returns a 1968 regulation by its No form only" do
    expect(code("EU Regulation No 2015/1968")).to eq "EU Regulation No 2015/1968"
    expect(code("EU Regulation 2015/1968")).to be_nil
  end

  it "returns a directive" do
    expect(code("EU Directive 2016/680")).to eq "EU Directive 2016/680"
  end

  it "returns a decision by its act number, not its CELEX number" do
    expect(code("EU Decision 2016/245")).to eq "EU Decision 2016/245"
    expect(code("EU Decision 2016/2")).to be_nil
  end

  it "returns a number-first decision" do
    expect(code("EU Decision 1082/2013")).to eq "EU Decision 1082/2013"
  end

  # Before 2015 a decision had two number series, so two acts can share a
  # number and a year: Council Decision No 252/2013/EU and Commission
  # Implementing Decision 2013/252/EU. pubid's `===` ignores the order, so
  # the search gives both rows, and the print order chooses.
  it "tells two decisions with one number and year apart by the order" do
    expect(code("EU Decision 252/2013")).to eq "EU Decision 252/2013"
    expect(code("EU Decision 2013/252")).to eq "EU Decision 2013/252"
  end

  it "accepts the pubid that Relaton::Db hands over" do
    pubid = Pubid::Eu::Identifier.parse "EU Regulation 1227/2011"
    expect(code(pubid)).to eq "EU Regulation 1227/2011"
  end

  it "compares the act type" do
    expect(code("EU Directive 1227/2011")).to be_nil
  end

  it "sets the fetch date when it reads a document" do
    item = described_class.get "EU Regulation 1227/2011"
    expect(item.fetched.to_s).to eq Date.today.to_s
  end

  it "answers nil for a reference pubid cannot read" do
    expect(code("EU Regulation 1227")).to be_nil
  end

  it "answers nil when the data repo has no document for a row" do
    stub_request(:get, %r{\A#{Regexp.escape Relaton::Eu::ENDPOINT}}o).to_return(status: 404)
    expect(code("EU Regulation 1227/2011")).to be_nil
  end

  it "raises a retryable error when the data repo fails" do
    stub_request(:get, %r{\A#{Regexp.escape Relaton::Eu::ENDPOINT}}o).to_return(status: 500)
    expect { code("EU Regulation 1227/2011") }.to raise_error Relaton::RequestError
  end
end
