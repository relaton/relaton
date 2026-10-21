# frozen_string_literal: true

require "relaton/nist/data_fetcher"

RSpec.describe "Relaton::Nist::DataFetcher#fetch_csrc (relaton#313)" do
  let(:fetcher) { Relaton::Nist::DataFetcher.new(output, "yaml") }
  let(:output) { @output }

  around { |ex| Dir.mktmpdir { |d| @output = d; ex.run } }

  # Real CSRC feed rows, from the fixture feed spec/support/webmock.rb
  # preloads. Copies, because #pubs_export_id normalizes a row in place.
  def feed_rows(&block)
    Relaton::Nist::PubsExport.instance.data.select(&block).map { |h| Marshal.load Marshal.dump(h) }
  end

  def files
    Dir[File.join(output, "*.yaml")].map { |f| File.basename(f) }
  end

  def primary_ids
    Dir[File.join(output, "*.yaml")].map do |f|
      Relaton::Nist::Item.from_yaml(File.read(f, encoding: "UTF-8"))
        .docidentifier.find(&:primary).content
    end
  end

  # The feed's FIPS 197 family: the 2023 update's initial public draft
  # (DOI NIST.FIPS.197-upd1.ipd), the 2023 update, and the 2001 original.
  let(:fips197) { feed_rows { |h| h["docidentifier"] == "FIPS 197" } }

  it "has the FIPS 197 family in the fixture feed" do
    expect(fips197.map { |h| h["uri"] }).to contain_exactly(
      "https://csrc.nist.gov/pubs/fips/197/ipd",
      "https://csrc.nist.gov/pubs/fips/197/final",
      "https://csrc.nist.gov/pubs/fips/197/final-(1)",
    )
  end

  it "writes the draft-stage record with the id the runtime gives it" do
    fetcher.fetch_csrc fips197
    expect(files.size).to eq 1
    expect(primary_ids).to eq ["NIST FIPS 197/Upd1 ipd"]
    yaml = File.read(File.join(output, files.first), encoding: "UTF-8")
    expect(yaml).to include("Advanced Encryption Standard (AES)")
    expect(yaml).to include("https://csrc.nist.gov/pubs/fips/197/ipd")
  end

  it "skips final rows — the finals come from the MODS pass" do
    fetcher.fetch_csrc(fips197.reject { |h| h["uri"].end_with?("/ipd") })
    expect(files).to be_empty
  end

  it "indexes the draft row under a stage-carrying pubid" do
    fetcher.fetch_csrc fips197
    hits = fetcher.index.search(
      ::Pubid::Nist::Identifier.parse("NIST FIPS 197/Upd1 ipd"),
    )
    expect(hits.size).to eq 1
    expect(hits.first[:id].stage).not_to be_nil
  end

  it "keeps numbered drafts and writes the canonical revision form" do
    drafts = feed_rows { |h| h["uri"].end_with?("/sp/1800/12/2pd", "/sp/800/108/r1/ipd") }
    expect(drafts.size).to eq 2
    fetcher.fetch_csrc drafts
    expect(primary_ids).to contain_exactly "NIST SP 1800-12 2pd", "NIST SP 800-108r1 ipd"
  end

  it "leaves an unchanged record untouched on the next crawl" do
    fetcher.fetch_csrc fips197
    file = Dir[File.join(output, "*.yaml")].first
    expect(File.read(file)).not_to include "fetched:"
    allow(Date).to receive(:today).and_return Date.new(2099, 1, 1)
    before = File.read(file)
    Relaton::Nist::DataFetcher.new(output, "yaml").fetch_csrc fips197
    expect(File.read(file)).to eq before
  end

  it "writes a draft republished at an -(N) uri once, from its plain uri" do
    drafts = feed_rows { |h| h["uri"].match?(%r{/sp/800/131/a/r3/ipd}) }
    expect(drafts.size).to eq 2
    expect(Relaton::Nist::Util).not_to receive(:warn)
    fetcher.fetch_csrc drafts.reverse
    expect(files.size).to eq 1
    yaml = File.read(Dir[File.join(output, "*.yaml")].first, encoding: "UTF-8")
    expect(yaml).to include "https://csrc.nist.gov/pubs/sp/800/131/a/r3/ipd\n"
  end

  it "lets a write error stop the crawl" do
    allow(fetcher).to receive(:force_write).and_raise Errno::ENOSPC
    expect { fetcher.fetch_csrc fips197 }.to raise_error Errno::ENOSPC
  end

  it "records a row that fails and still writes the next one" do
    bad = { "docidentifier" => "FIPS 1", "uri" => "https://csrc.nist.gov/pubs/fips/1/ipd" }
    expect { fetcher.fetch_csrc [bad, *fips197] }.not_to raise_error
    expect(files.size).to eq 1
    expect(fetcher.failures).to include(/CSRC record skipped.*FIPS 1, /)
  end

  it "names the related document in a relation, not the record itself" do
    ipd = fips197.find { |h| h["uri"].end_with?("/ipd") }
    ipd["superseded-by"] = [{ "uri" => "https://csrc.nist.gov/pubs/fips/197/final",
                              "docidentifier" => "FIPS 197" }]
    fetcher.fetch_csrc [ipd]
    rel = Relaton::Nist::Item.from_yaml(File.read(File.join(output, files.first), encoding: "UTF-8"))
      .relation.first
    expect(rel.type).to eq "updates"
    # The /fips/197/final row is the 2023 update (DOI NIST.FIPS.197-upd1).
    expect(rel.bibitem.docidentifier.map(&:content)).to eq ["NIST FIPS 197/Upd1"]
  end

  it "derives a related id from the entry when the feed lacks the related row" do
    ipd = fips197.find { |h| h["uri"].end_with?("/ipd") }
    ipd["supersedes"] = [{ "uri" => "https://csrc.nist.gov/pubs/sp/800/999/ipd",
                           "docidentifier" => "SP 800-999" }]
    fetcher.fetch_csrc [ipd]
    rel = Relaton::Nist::Item.from_yaml(File.read(File.join(output, files.first), encoding: "UTF-8"))
      .relation.first
    expect(rel.bibitem.docidentifier.map(&:content)).to eq ["NIST SP 800-999 ipd"]
  end
end
