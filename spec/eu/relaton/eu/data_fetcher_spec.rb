describe Relaton::Eu::DataFetcher, :no_index_fixture do
  around do |example|
    Dir.mktmpdir("relaton-eu-crawl") do |dir|
      @dir = dir
      Dir.chdir(dir) { example.run }
    end
  end

  before { stub_cellar }

  def crawl(**opts)
    described_class.fetch("eu-cellar", output: "data", format: "yaml", **opts)
  end

  def index_rows
    YAML.safe_load_file("#{Relaton::Eu::INDEXFILE}.yaml", permitted_classes: [Symbol])
  end

  it "rejects an unknown source" do
    expect { described_class.new("data", "yaml").fetch("eur-lex") }
      .to raise_error ArgumentError, /eu-cellar/
  end

  def cellar_requests(pattern)
    a_request(:get, /#{Regexp.escape Relaton::Eu::Cellar::URL}/o).with do |req|
      URI.decode_www_form(req.uri.query).to_h.fetch("query").match?(pattern)
    end
  end

  it "asks CELLAR for every year from 1952: a count, then the pages" do
    crawl
    years = Date.today.year - 1952 + 1
    expect(cellar_requests(/COUNT\(DISTINCT/)).to have_been_made.times(years)
    expect(cellar_requests(/OFFSET 0\b/)).to have_been_made.times(years)
  end

  # Every fixture year is shorter than a 1,000-row page, so the page size is
  # cut to 2: 2016 (5 works) then takes three pages.
  it "reads a year page by page" do
    stub_const "Relaton::Eu::Cellar::ROWS", 2
    crawl
    expect(index_rows.size).to eq 7
    expect(cellar_requests(/resource_legal_year "2016".*OFFSET (0|2|4)\b/m))
      .to have_been_made.times(3)
    expect(cellar_requests(/OFFSET 6\b/)).not_to have_been_made
  end

  it "writes one file per act, named after the act identifier" do
    crawl
    expect(Dir["data/*.yaml"].map { |f| File.basename f }.sort).to eq %w[
      eu-decision-1082-2013.yaml eu-decision-2016-245.yaml
      eu-directive-1993-42.yaml eu-directive-2016-680.yaml
      eu-regulation-1227-2011.yaml eu-regulation-2016-1356.yaml
      eu-regulation-2016-679.yaml
    ]
  end

  it "writes documents the generic model reads back" do
    crawl
    item = Relaton::Bib::Item.from_yaml File.read("data/eu-regulation-1227-2011.yaml")
    expect(item.docidentifier.first.content).to eq "EU Regulation 1227/2011"
  end

  it "indexes each act under its pubid" do
    crawl
    rows = index_rows
    expect(rows.size).to eq 7
    row = rows.find { |r| r[:file] == "data/eu-regulation-1227-2011.yaml" }
    expect(row[:id]).to eq("_type" => "pubid:eu:regulation", "number" => "1227",
                           "year" => "2011")
  end

  it "keeps the print order in the index row of a number-first decision" do
    crawl
    row = index_rows.find { |r| r[:file] == "data/eu-decision-1082-2013.yaml" }
    expect(row[:id]).to include("number" => "1082", "year" => "2013",
                                "number_first" => true)
  end

  # The ratio guard of `prune_unwritten` (90 %) is core's; with seven acts
  # one stale file is above it, so the ratio is lowered here. What this
  # checks is that the crawl records every file it writes.
  it "records each file it writes, so a prune deletes only a stale one" do
    FileUtils.mkdir_p "data"
    File.write "data/eu-regulation-1-1999.yaml", "old"
    fetcher = described_class.new("data", "yaml")
    fetcher.prune = true
    fetcher.fetch("eu-cellar")
    expect(fetcher.prune_unwritten(min_ratio: 0.5)).to eq ["data/eu-regulation-1-1999.yaml"]
    expect(Dir["data/*.yaml"].size).to eq 7
  end

  it "starts from an empty index: a row of an earlier run does not stay" do
    File.write "#{Relaton::Eu::INDEXFILE}.yaml", [
      { id: { "_type" => "pubid:eu:regulation", "number" => "1", "year" => "1999" },
        file: "data/eu-regulation-1-1999.yaml" },
    ].to_yaml
    crawl
    expect(index_rows.map { |r| r[:file] }).not_to include "data/eu-regulation-1-1999.yaml"
    expect(index_rows.size).to eq 7
  end

  # One act, two works whose titles print the pair in opposite orders: the
  # printed ids differ, the act does not.
  it "keeps one work of an act whose works print it in two orders" do
    twin = CellarStub.rows("2013").first.merge(
      "celex" => { "value" => "32013D1082(99)" },
      "title" => { "value" => "Decision 2013/1082/EU of the European Parliament" },
    )
    rows = ->(year) { year == "2013" ? CellarStub.rows(year) + [twin] : CellarStub.rows(year) }
    stub_request(:get, /#{Regexp.escape Relaton::Eu::Cellar::URL}/o)
      .to_return { |req| CellarStub.response(req, rows: rows) }
    crawl
    expect(index_rows.count { |r| r[:id]["number"] == "1082" }).to eq 1
    expect(Dir["data/eu-decision-*2013*.yaml"]).to eq ["data/eu-decision-1082-2013.yaml"]
  end

  it "reports a covered ELI that pubid cannot read" do
    bad = CellarStub.rows("2011").find { |b| b.dig("celex", "value") == "32011R1227" }
                    .merge("eli" => { "value" => "http://data.europa.eu/eli/reg/2011/0/oj" })
    rows = ->(year) { year == "2011" ? [bad] : CellarStub.rows(year) }
    stub_request(:get, /#{Regexp.escape Relaton::Eu::Cellar::URL}/o)
      .to_return { |req| CellarStub.response(req, rows: rows) }
    expect(Relaton::Eu::Util).to receive(:error).with(%r{CELEX 32011R1227: pubid cannot read ELI `http://data.europa.eu/eli/reg/2011/0/oj`})
    crawl
    expect(File.exist?("data/eu-regulation-1227-2011.yaml")).to be false
  end

  context "when CELLAR fails" do
    before { allow_any_instance_of(Relaton::Eu::Cellar).to receive(:sleep) }

    it "retries a server error" do
      calls = 0
      stub_request(:get, /#{Regexp.escape Relaton::Eu::Cellar::URL}/o).to_return do |req|
        calls += 1
        calls == 1 ? { status: 503 } : CellarStub.response(req)
      end
      crawl
      expect(File.exist?("data/eu-regulation-1227-2011.yaml")).to be true
    end

    it "raises before it writes the index when a page keeps failing" do
      stub_request(:get, /#{Regexp.escape Relaton::Eu::Cellar::URL}/o)
        .to_return(status: 503)
      expect { crawl prune: true }.to raise_error Relaton::RequestError, /CELLAR/
      expect(File.exist?("#{Relaton::Eu::INDEXFILE}.yaml")).to be false
    end

    it "raises when a year reads fewer works than CELLAR counts" do
      short = ->(year) { year == "2016" ? CellarStub.rows(year).first(3) : CellarStub.rows(year) }
      stub_request(:get, /#{Regexp.escape Relaton::Eu::Cellar::URL}/o).to_return do |req|
        query = URI.decode_www_form(req.uri.query).to_h.fetch("query")
        query.include?("COUNT(DISTINCT") ? CellarStub.response(req) : CellarStub.response(req, rows: short)
      end
      expect { crawl prune: true }.to raise_error Relaton::RequestError, /3 of 5 works for year 2016/
      expect(File.exist?("#{Relaton::Eu::INDEXFILE}.yaml")).to be false
    end

    it "raises on an answer Virtuoso marks incomplete" do
      stub_request(:get, /#{Regexp.escape Relaton::Eu::Cellar::URL}/o).to_return do |req|
        CellarStub.response(req).merge(
          headers: { "Content-Type" => "application/sparql-results+json",
                     "X-SQL-State" => "S1TAT", "X-SQL-Message" => "RC...: Returning incomplete results" },
        )
      end
      expect { crawl }.to raise_error Relaton::RequestError, /incomplete for year 1952 count: S1TAT/
    end

    it "raises on an answer it cannot retry" do
      stub_request(:get, /#{Regexp.escape Relaton::Eu::Cellar::URL}/o)
        .to_return(status: 400)
      expect { crawl }.to raise_error Relaton::RequestError, /HTTP 400/
    end
  end
end
