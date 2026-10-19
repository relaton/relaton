# frozen_string_literal: true

RSpec.describe "Relaton::Nist::DataFetcher#fetch_csrc (relaton#313)" do
  let(:fetcher) { Relaton::Nist::DataFetcher.new(output, "yaml") }
  let(:output) { @output }

  around { |ex| Dir.mktmpdir { |d| @output = d; ex.run } }

  # Real CSRC feed rows (the feed's FIPS 197 family: the upd1 ipd draft and
  # the final).
  let(:rows) do
    [
      {
        "series" => "nist-fips", "docnumber" => "197",
        "docidentifier" => "FIPS 197",
        "uri" => "https://csrc.nist.gov/pubs/fips/197/ipd",
        "title-main" => "Advanced Encryption Standard (AES)",
        "issued-date" => "2025-11-05",
      },
      {
        "series" => "nist-fips", "docnumber" => "197",
        "docidentifier" => "FIPS 197",
        "uri" => "https://csrc.nist.gov/pubs/fips/197/final",
        "title-main" => "Advanced Encryption Standard (AES)",
      },
    ]
  end

  it "writes the draft-stage record with its stage-carrying docidentifier" do
    fetcher.fetch_csrc rows
    files = Dir[File.join(output, "*.yaml")].map { |f| File.basename(f) }
    expect(files).to eq ["nist-fips-197-ipd.yaml"]
    yaml = File.read(File.join(output, files.first))
    expect(yaml).to include("NIST FIPS 197 ipd")
    expect(yaml).to include("Advanced Encryption Standard (AES)")
  end

  it "skips final rows — the finals come from the MODS pass" do
    fetcher.fetch_csrc [rows.last]
    expect(Dir[File.join(output, "*.yaml")]).to be_empty
  end

  it "indexes the draft row so the consumer search finds it" do
    fetcher.fetch_csrc rows
    hits = fetcher.index.search(
      ::Pubid::Nist::Identifier.parse("NIST FIPS 197 ipd")
    )
    expect(hits).not_to be_empty
  end
end
