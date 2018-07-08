require "spec_helper"

RSpec.describe Relaton::Db do
  it "rejects an illegal reference prefix" do
    system "rm testcache.json testcache2.json"
    db = Relaton::Db.new("testcache.json", "testcache2.json")
    expect{db.fetch("XYZ XYZ", nil, {})}.to output(/does not have a recognised prefix/).to_stderr
    db.save()
    expect(File.exist?("testcache.json")).to be true
    expect(File.exist?("testcache2.json")).to be true
    testcache = File.read "testcache.json"
    expect(testcache).to eq "{}"
    testcache = File.read "testcache2.json"
    expect(testcache).to eq "{}"
  end

  it "gets an ISO reference and caches it" do
    mock_algolia 1
    mock_http_net 2
    system "rm testcache.json testcache2.json"
    db = Relaton::Db.new("testcache.json", "testcache2.json")
    bib = db.fetch("ISO 19115-1", nil, {})
    expect(bib).to include "<bibitem type=\"international-standard\" id=\"ISO19115-1\">"
    db.save()
    expect(File.exist?("testcache.json")).to be true
    expect(File.exist?("testcache2.json")).to be true
    testcache = File.read "testcache.json"
    expect(testcache).to include "<bibitem type=\\\"international-standard\\\" id=\\\"ISO19115-1\\\">"
    testcache = File.read "testcache2.json"
    expect(testcache).to include "<bibitem type=\\\"international-standard\\\" id=\\\"ISO19115-1\\\">"
  end

  it "deals with a non-existant ISO reference" do
    mock_algolia 2
    system "rm testcache.json testcache2.json"
    db = Relaton::Db.new("testcache.json", "testcache2.json")
    bib = db.fetch("ISO 111111119115-1", nil, {})
    expect(bib).to be_nil
    db.save()
    expect(File.exist?("testcache.json")).to be true
    expect(File.exist?("testcache2.json")).to be true
    testcache = File.read "testcache.json"
    expect(testcache).to include %("ISO 111111119115-1":null)
    testcache = File.read "testcache2.json"
    expect(testcache).to include %("ISO 111111119115-1":null)
  end


  private

  # rubocop:disable Naming/UncommunicativeBlockParamName, Naming/VariableName
  # rubocop:disable Metrics/AbcSize
  # Mock xhr rquests to Algolia.
  def mock_algolia(num)
    index = double 'index'
    expect(index).to receive(:search) do |text, facetFilters:, page: 0|
      expect(text).to be_instance_of String
      expect(facetFilters[0]).to eq 'category:standard'
      JSON.parse File.read "spec/support/algolia_resp_page_#{page}.json"
    end.exactly(num).times
    expect(Algolia::Index).to receive(:new).with('all_en').and_return index
  end
  # rubocop:enable Naming/UncommunicativeBlockParamName, Naming/VariableName
  # rubocop:enable Metrics/AbcSize

  # Mock http get pages requests.
  def mock_http_net(num)
    expect(Net::HTTP).to receive(:get_response).with(kind_of(URI)) do |uri|
      if uri.path.match? %r{\/contents\/}
        # When path is from json response then redirect.
        resp = Net::HTTPMovedPermanently.new '1.1', '301', 'Moved Permanently'
        resp['location'] = "/standard/#{uri.path.match(/\d+\.html$/)}"
      else
        # In other case return success response with body.
        resp = double_resp uri
      end
      resp
    end.exactly(num).times
  end

  def double_resp(uri)
    resp = double 'resp'
    expect(resp).to receive(:body) do
      File.read "spec/support/#{uri.path.tr('/', '_')}"
    end.at_least :once
    expect(resp).to receive(:code).and_return('200').at_most :once
    resp
  end
end
