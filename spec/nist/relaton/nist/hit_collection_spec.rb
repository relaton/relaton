RSpec.describe Relaton::Nist::HitCollection do
  subject { Relaton::Nist::HitCollection.new "NIST IR 8200" }

  it "raise error when HTTP response isn't 200 or 404" do
    io = double "OpenURI IO", status: ["500"]
    error = OpenURI::HTTPError.new("", io)
    expect(Relaton::Index).to receive(:find_or_create).and_raise error
    expect { subject.send(:from_ga) }.to raise_error error
  end

  describe "#from_ga (index-v2)" do
    it "returns pubid-derived hits from the index-v2 fixture" do
      hits = subject.send(:from_ga)
      expect(hits).to all(be_instance_of(Relaton::Nist::Hit))
      hit = hits.find { |h| h.hit[:code] == "NIST IR 8200" }
      expect(hit).not_to be_nil
      # index-v2 stores Pubid objects; the boundary stringifies :id and
      # carries the data file path through unchanged (don't pin the exact
      # filename — the fixture is refreshed by rake spec:update_index).
      expect(hit.hit[:code]).to be_instance_of(String)
      expect(hit.hit[:path]).to match(%r{nistir-8200.*\.yaml\z})
    end

    it "falls back to a string lookup for an unparseable reference without raising" do
      hc = Relaton::Nist::HitCollection.new ")(*&^ not a ref"
      # The pubid parse fails, so from_ga uses the raw string for the index
      # lookup; the key property is that it doesn't raise (and finds nothing).
      result = nil
      expect { result = hc.send(:from_ga) }.not_to raise_error
      expect(result).to eq []
    end
  end

  it "sort hits" do
    expect(subject).to receive(:from_json).and_return [
      Relaton::Nist::Hit.new({ status: "withdrawn", code: "B", release_date: Date.today }, subject),
      Relaton::Nist::Hit.new({ status: "draft", code: "A", release_date: Date.today }, subject),
    ]
    subj = subject.search
    expect(subj).to be subject
  end

  it "sort_hits! prefers higher /Upd for the same base code" do
    hits = [
      Relaton::Nist::Hit.new({ code: "NIST FIPS 140-2",      release_date: Date.new(2001, 5, 25) }, subject),
      Relaton::Nist::Hit.new({ code: "NIST FIPS 140-2/Upd1", release_date: Date.new(2001, 10, 10) }, subject),
      Relaton::Nist::Hit.new({ code: "NIST FIPS 140-2/Upd2", release_date: Date.new(2002, 12, 3) }, subject),
    ]
    subject.instance_variable_set :@array, hits
    subject.send :sort_hits!
    expect(subject.array.map { |h| h.hit[:code] }).to eq [
      "NIST FIPS 140-2/Upd2",
      "NIST FIPS 140-2/Upd1",
      "NIST FIPS 140-2",
    ]
  end

  it "sort_hits! keeps distinct base codes in alphabetical order" do
    hits = [
      Relaton::Nist::Hit.new({ code: "NIST SP 800-12r1", release_date: Date.new(2017, 6, 22) }, subject),
      Relaton::Nist::Hit.new({ code: "NIST SP 800-12",   release_date: Date.new(1995, 10, 2) }, subject),
    ]
    subject.instance_variable_set :@array, hits
    subject.send :sort_hits!
    expect(subject.array.first.hit[:code]).to eq "NIST SP 800-12"
  end

  describe "#pubs_export_id" do
    let(:hc) { Relaton::Nist::HitCollection.new "NIST FIPS 140-2" }

    def call(json)
      hc.send(:pubs_export_id, json)
    end

    it "leaves the feed row unchanged (the crawler and the runtime share it)" do
      json = { "docidentifier" => +"SP 800-999-draft", "uri" => "https://csrc.nist.gov/pubs/sp/800/999/ipd" }
      expect(call(json)).to eq "NIST SP 800-999 ipd"
      expect(json["docidentifier"]).to eq "SP 800-999-draft"
    end

    it "final iteration => no stage" do
      expect(call(
        "doi" => "10.6028/NIST.FIPS.140-2",
        "docidentifier" => "FIPS 140-2",
        "uri" => "https://csrc.nist.gov/pubs/fips/140-2/final",
        "iteration" => "final",
      )).to eq "NIST FIPS 140-2"
    end

    it "final iteration with /upd2/final URI => no stage, update set" do
      expect(call(
        "doi" => "10.6028/NIST.FIPS.140-2",
        "docidentifier" => "FIPS 140-2",
        "uri" => "https://csrc.nist.gov/pubs/fips/140-2/upd2/final",
        "iteration" => "final",
      )).to eq "NIST FIPS 140-2/Upd2"
    end

    it "ipd iteration => ipd stage" do
      expect(call(
        "doi" => "10.6028/NIST.SP.800-189.ipd",
        "docidentifier" => "SP 800-189",
        "uri" => "https://csrc.nist.gov/pubs/sp/800/189/ipd",
        "iteration" => "ipd",
      )).to match(/ipd$/)
    end

    it "fpd iteration => fpd stage" do
      expect(call(
        "doi" => "10.6028/NIST.SP.800-189.fpd",
        "docidentifier" => "SP 800-189",
        "uri" => "https://csrc.nist.gov/pubs/sp/800/189/fpd",
        "iteration" => "fpd",
      )).to match(/fpd$/)
    end

    it "2pd iteration => 2pd stage" do
      expect(call(
        "doi" => "10.6028/NIST.SP.800-189.2pd",
        "docidentifier" => "SP 800-189",
        "uri" => "https://csrc.nist.gov/pubs/sp/800/189/2pd",
        "iteration" => "2pd",
      )).to match(/2pd$/)
    end

    it "URI ipd overrides DOI fpd and iteration final" do
      expect(call(
        "doi" => "10.6028/NIST.SP.800-157r1.fpd",
        "docidentifier" => "SP 800-157 Rev. 1",
        "uri" => "https://csrc.nist.gov/pubs/sp/800/157/r1/ipd",
        "iteration" => "final",
      )).to match(/ipd$/)
    end

    it "nil iteration and no stage in URI => no stage" do
      expect(call(
        "doi" => "10.6028/NIST.FIPS.140-2",
        "docidentifier" => "FIPS 140-2",
        "uri" => "https://csrc.nist.gov/pubs/fips/140-2/final",
        "iteration" => nil,
      )).to eq "NIST FIPS 140-2"
    end
  end
end

RSpec.describe "Relaton::Nist::HitCollection stage-carrying references (relaton#146)" do
  it "retries the stage-excluded reference when the stage-narrowed search misses" do
    hc = Relaton::Nist::HitCollection.new "NIST FIPS 197 fpd"
    hits = hc.send(:from_ga)
    codes = hits.map { |h| h.hit[:code] }
    # The published index has no stage-typed row for the fpd; the base
    # document of the family answers instead.
    expect(codes).to include("NIST FIPS 197")
  end

  it "search_filter equalizes the stage on both sides of the equality" do
    filtered = Relaton::Nist::HitCollection.search("NIST FIPS 197 fpd").search_filter
    expect(filtered).not_to be_empty
    expect(filtered.map { |h| h.hit[:code] }).to include("NIST FIPS 197")
  end
end

RSpec.describe "Relaton::Nist stage-carrying resolution (relaton#313/#146)" do
  it "sorts the stage-matching hit first for a stage-carrying reference" do
    hc = Relaton::Nist::HitCollection.new "NIST FIPS 197 ipd"
    hits = hc.search
    expect(hits.first.hit[:code]).to match(/ipd\z/)
  end
end

RSpec.describe "Relaton::Nist exact stage match (relaton#314)" do
  # The exact-stage branch of search_filter returned early, and the method's
  # ensure then replaced the result with the unset fallback (array = nil), so
  # every reference that named its own stage-typed row crashed.
  it "keeps the exact stage-typed hit for a reference that names it" do
    hits = Relaton::Nist::HitCollection.search("NIST FIPS 197/Upd1 ipd")
    codes = hits.search_filter.array.map { |h| h.hit[:code] }
    expect(codes).to eq ["NIST FIPS 197/Upd1 ipd"]
  end

  it "resolves the reference through Bibliography.get" do
    item = Relaton::Nist::Bibliography.get "NIST FIPS 197/Upd1 ipd"
    expect(item.docidentifier.first.content).to eq "NIST FIPS 197/Upd1 ipd"
  end
end

RSpec.describe "Relaton::Nist CSWP comes from CSRC (relaton-nist#104)" do
  # The NIST Library's MODS feed has no CSWP record, so the index holds only
  # the CSRC draft rows. A final CSWP must answer from the CSRC feed, which
  # the search asks before the index.
  it "answers a final CSWP from the CSRC feed without the index" do
    hc = Relaton::Nist::HitCollection.new "NIST CSWP 29"
    expect(hc).not_to receive(:from_ga)
    hits = hc.search.search_filter.array
    final = hits.find { |h| h.hit[:json]["iteration"] == "final" }
    expect(final.hit[:code]).to eq "NIST CSWP 29"
  end

  it "resolves the reference through Bibliography.get" do
    item = Relaton::Nist::Bibliography.get "NIST CSWP 29"
    expect(item.docidentifier.first.content).to eq "NIST CSWP 29"
    expect(item.source.map { |s| s.content.to_s }).to include(
      "https://csrc.nist.gov/pubs/cswp/29/the-nist-cybersecurity-framework-csf-20/final",
    )
  end
end
