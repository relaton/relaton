require "tmpdir"
require "json"
require "relaton/cli/index_site_generator"

RSpec.describe Relaton::Cli::IndexSiteGenerator do
  let(:data_dir) { "spec/index_fixtures/data" }
  let(:dist_dir) { File.expand_path("spec/index_fixtures/dist") }

  # Point FrontendAssets at the fixture bundle so specs never need a Node build.
  around do |example|
    Dir.mktmpdir("index-spec-") do |out|
      @out = out
      Relaton::Cli::FrontendAssets.with_dist_dir(dist_dir) { example.run }
    end
  end

  def generate(opts = {})
    described_class.generate(
      data_dir,
      { output: @out, title: "BIPM Index", generated: "2026-01-01",
        base_url: "https://raw.githubusercontent.com/relaton/relaton-data-bipm/v2" }.merge(opts),
    )
    File.read(File.join(@out, "index.html"), encoding: "utf-8")
  end

  it "returns the path to index.html and writes search.json" do
    path = described_class.generate(data_dir, output: @out, generated: "2026-01-01")
    expect(path).to eq(File.join(@out, "index.html"))
    expect(File).to exist(File.join(@out, "search.json"))
  end

  it "skips the machine index-v*.yaml and indexes only documents" do
    html = generate
    # 2 documents (ccri/21, cgpm/26); index-v1.yaml is skipped.
    expect(html.scan(/class="document"/).size).to eq(2)
  end

  it "renders the rendered primary DocID and title from the document itself" do
    html = generate
    expect(html).to include('data-id="CCRI 21st Meeting (2009)"')
    expect(html).to include("21st meeting of the CCRI")
  end

  it "builds the raw-YAML link from base_url + repo-relative path" do
    html = generate
    expect(html).to include(
      'data-href="https://raw.githubusercontent.com/relaton/relaton-data-bipm/v2/data/ccri/meeting/21.yaml"',
    )
  end

  it "inlines the compiled bundle (IIFE + CSS)" do
    html = generate
    expect(html).to include("fake IIFE for specs")
    expect(html).to include("fake style for specs")
    expect(html).to include('id="relaton-index-app"')
  end

  context "embedded mode (default)" do
    it "emits both the crawler DOM and the escaped JSON payload" do
      html = generate
      expect(html).to include("window.RELATON_INDEX_DATA = {")
      expect(html).to include('class="document"')
      # crawler DOM present for indexing
      expect(html).to include("data-search=")
    end

    it "escapes </ inside the embedded JSON so it can't close the script tag" do
      html = generate
      json = html[/window\.RELATON_INDEX_DATA = (.+?);<\/script>/m, 1]
      expect(json).to be_a(String)
      expect(JSON.parse(json)["documents"].size).to eq(2)
    end
  end

  context "dom mode" do
    it "omits the injected JSON but keeps the crawler DOM" do
      html = generate(mode: "dom")
      expect(html).not_to include("window.RELATON_INDEX_DATA = {")
      expect(html.scan(/class="document"/).size).to eq(2)
    end
  end

  context "static-json mode" do
    it "adds data-src and omits the crawler DOM and injected JSON" do
      html = generate(mode: "static-json")
      expect(html).to include('data-src="search.json"')
      expect(html).not_to include("window.RELATON_INDEX_DATA = {")
      expect(html).not_to include('class="document"')
    end

    it "writes a search.json with compact records" do
      generate(mode: "static-json")
      rows = JSON.parse(File.read(File.join(@out, "search.json")))
      expect(rows.size).to eq(2)
      expect(rows.first.keys).to include("r", "c", "t", "d", "u")
    end
  end

  context "when the frontend bundle is missing" do
    it "raises an actionable error" do
      Dir.mktmpdir do |empty|
        Relaton::Cli::FrontendAssets.with_dist_dir(empty) do
          expect { described_class.generate(data_dir, output: @out) }
            .to raise_error(Relaton::Cli::FrontendAssets::BuildMissingError, /rake build_frontend/)
        end
      end
    end
  end

  it "rejects an unknown mode" do
    expect { described_class.generate(data_dir, output: @out, mode: "bogus") }
      .to raise_error(ArgumentError, /Unknown mode/)
  end
end
