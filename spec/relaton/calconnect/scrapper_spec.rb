describe Relaton::Calconnect::Scraper do
  let(:errors) { {} }
  let(:scraper) { described_class.new(errors) }
  let(:hit) do
    {
      "id" => "cc-18011-2018",
      "edition" => "1",
      "source" => {
        "owner" => "CalConnect",
        "repo" => "cc-datetime-explicit",
        "tag" => "cc-18011-2018/ed1",
      },
    }
  end
  let(:rxl) do
    <<~XML
      <bibdata type="standard">
        <title language="en" type="main">Date and time — Explicit representation</title>
        <docidentifier type="CalConnect" primary="true">CC 18011:2018</docidentifier>
      </bibdata>
    XML
  end

  it "#release_zip_url" do
    expect(scraper.send(:release_zip_url, hit)).to eq(
      "https://github.com/CalConnect/cc-datetime-explicit/releases/download/" \
      "cc-18011-2018/ed1/cc-18011-2018-ed1.zip",
    )
  end

  it "#release_zip_url for working-draft tag" do
    wd_hit = {
      "id" => "cc-wd-58020-2016",
      "edition" => "1",
      "source" => { "owner" => "CalConnect", "repo" => "cc-vpatch", "tag" => "cc-wd-58020-2016/ed1-wd" },
    }
    expect(scraper.send(:release_zip_url, wd_hit)).to end_with "/cc-wd-58020-2016-ed1-wd.zip"
  end

  it "#rxl_filename" do
    expect(scraper.send(:rxl_filename, hit)).to eq "cc-18011-2018-ed1.rxl"
  end

  it "#normalize_rxl rewrites technical-committee element and adds primary to CC/csd ids" do
    xml = <<~XML
      <bibdata>
        <docidentifier type="csd">x</docidentifier>
        <technical-committee>TC</technical-committee>
        <subdivision type="Technical committee"><name>X</name></subdivision>
      </bibdata>
    XML
    out = scraper.send(:normalize_rxl, xml)
    expect(out).to include "<committee>TC</committee>"
    expect(out).to include 'type="csd" primary="true"'
    expect(out).to include '<subdivision type="technical-committee">'
  end

  it "#parse_page downloads release zip, extracts rxl, and parses it" do
    expect(scraper).to receive(:download_release_zip).with(hit).and_return :zip_bytes
    expect(scraper).to receive(:extract_rxl).with(:zip_bytes, "cc-18011-2018-ed1.rxl").and_return rxl
    bib = scraper.parse_page(hit)
    expect(bib).to be_instance_of Relaton::Calconnect::ItemData
    expect(bib.docidentifier.first.content).to eq "CC 18011:2018"
  end

  it "#download_release_zip uses Mechanize and returns the body" do
    resp = double "Mechanize file", body: :zip_bytes
    agent = double "Mechanize agent"
    expect(agent).to receive(:get)
      .with("https://github.com/CalConnect/cc-datetime-explicit/releases/download/cc-18011-2018/ed1/cc-18011-2018-ed1.zip")
      .and_return resp
    expect(scraper).to receive(:agent).and_return agent
    expect(scraper.send(:download_release_zip, hit)).to eq :zip_bytes
  end

  it "#download_release_zip wraps HTTP errors with a descriptive message" do
    page = double "Mechanize page", code: "404"
    agent = double "Mechanize agent"
    expect(agent).to receive(:get).and_raise Mechanize::ResponseCodeError.new(page)
    expect(scraper).to receive(:agent).and_return agent
    expect { scraper.send(:download_release_zip, hit) }
      .to raise_error(/Failed to download release zip .+: HTTP 404/)
  end
end
