require "tmpdir"

RSpec.describe "Relaton index" do
  let(:data_dir) { "spec/index_fixtures/data" }
  let(:dist_dir) { File.expand_path("spec/index_fixtures/dist") }

  around do |example|
    Dir.mktmpdir("index-acc-") do |out|
      @out = out
      Relaton::Cli::FrontendAssets.with_dist_dir(dist_dir) { example.run }
    end
  end

  it "generates a browsable index site from a data folder" do
    Relaton::Cli.start(["index", data_dir, "-o", @out, "-t", "BIPM Index"])

    index = File.join(@out, "index.html")
    expect(File).to exist(index)
    expect(File).to exist(File.join(@out, "search.json"))

    html = File.read(index)
    expect(html).to include('id="relaton-index-app"')
    expect(html).to include('class="document"')
    expect(html).to include("window.RELATON_INDEX_DATA = {")
    expect(html).to include("BIPM Index")
  end

  it "honours --description and --favicon" do
    Relaton::Cli.start(["index", data_dir, "-o", @out,
                        "--description", "The BIPM standards index.",
                        "--favicon", "https://www.bipm.org/favicon.svg"])

    html = File.read(File.join(@out, "index.html"))
    expect(html).to include('<meta name="description" content="The BIPM standards index.">')
    expect(html).to include(
      '<link rel="icon" href="https://www.bipm.org/favicon.svg" type="image/svg+xml">',
    )
    expect(html).to include('data-description="The BIPM standards index."')
  end

  it "omits the description and favicon tags when the flags are absent" do
    Relaton::Cli.start(["index", data_dir, "-o", @out])

    html = File.read(File.join(@out, "index.html"))
    expect(html).not_to include('name="description"')
    expect(html).not_to include('rel="icon"')
  end

  it "honours --mode static-json" do
    Relaton::Cli.start(["index", data_dir, "-o", @out, "-m", "static-json"])

    html = File.read(File.join(@out, "index.html"))
    expect(html).to include('data-src="search.json"')
    expect(html).not_to include("window.RELATON_INDEX_DATA = {")
  end

  context "with a sibling static/ folder" do
    let(:data_dir) { "spec/index_fixtures_static/data" }

    it "includes the static/ docs in the generated site by default" do
      Relaton::Cli.start(["index", data_dir, "-o", @out])

      html = File.read(File.join(@out, "index.html"))
      expect(html).to include("NIST Research Library (2022)")
      expect(html).to include("JCGM 100 (2008)")
    end

    it "omits the static/ docs with --no-static" do
      Relaton::Cli.start(["index", data_dir, "-o", @out, "--no-static"])

      html = File.read(File.join(@out, "index.html"))
      expect(html).not_to include("NIST Research Library (2022)")
    end
  end
end
