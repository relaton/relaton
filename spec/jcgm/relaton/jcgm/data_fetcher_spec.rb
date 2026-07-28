# frozen_string_literal: true

require "relaton/jcgm/data_fetcher"
require "tmpdir"
require "fileutils"

RSpec.describe Relaton::Jcgm::DataFetcher do
  let(:fixtures) { File.expand_path("../../fixtures", __dir__) }

  # Reload the freshly-written index through Relaton::Index so each row's :id is
  # a Pubid::Jcgm identifier (avoids hand-parsing the symbol-keyed YAML).
  def index_rows
    Relaton::Index::Type.new(:jcgm, nil, "index-v1.yaml", nil, ::Pubid::Jcgm::Identifier).index
  end

  around do |example|
    Dir.mktmpdir("relaton-jcgm-df") do |tmp|
      # Stage the source (bipm-data-outcomes) and static fixtures in a workdir.
      FileUtils.cp_r File.join(fixtures, "bipm-data-outcomes"), tmp
      FileUtils.cp_r File.join(fixtures, "static"), tmp
      # Drop the pooled :JCGM index the suite preloads (the committed fixture)
      # so the DataFetcher builds a fresh index in this tmpdir instead of
      # reusing/polluting the shared pool across examples.
      Relaton::Index.close(:jcgm)
      Dir.chdir(tmp) { example.run }
      Relaton::Index.close(:jcgm)
    end
  end

  describe "harvesting meetings from bipm-data-outcomes" do
    before { described_class.fetch("bipm-data-outcomes", output: "data", format: "yaml") }

    it "writes one proceedings YAML per meeting" do
      expect(File).to exist("data/jcgm/meeting/17.yaml")
      expect(File).to exist("data/jcgm/meeting/11.yaml")
    end

    it "builds the meeting docnumber with the naive ordinal" do
      item = Relaton::Jcgm::Item.from_yaml(File.read("data/jcgm/meeting/17.yaml"))
      expect(item.docnumber).to eq "JCGM 17th Meeting (2012)"
      item11 = Relaton::Jcgm::Item.from_yaml(File.read("data/jcgm/meeting/11.yaml"))
      expect(item11.docnumber).to eq "JCGM 11st Meeting (2006)"
    end

    it "stores each meeting under a pubid:jcgm:meeting index row" do
      rows = index_rows
      types = rows.map { |r| r[:id].to_hash["_type"] }
      expect(types).to all(eq("pubid:jcgm:meeting"))
      expect(rows.map { |r| r[:file] }).to include("data/jcgm/meeting/17.yaml")
    end
  end

  # The curated static guides are indexed by the data repo's crawler, which
  # loops `static/**` and calls the public, guarded #add_to_index (the mechanism
  # under test here). The gem no longer owns the static loop.
  describe "#add_to_index (used by the data repo crawler for static guides)" do
    subject(:fetcher) { described_class.new("data", "yaml") }

    def index_static
      Dir["static/**/*.{yml,yaml}"].sort.each do |f|
        doc = YAML.safe_load_file(f, permitted_classes: [Date, Time])
        fetcher.add_to_index doc["docnumber"], f
      end
      fetcher.index.save
    end

    it "indexes the static guides with their pubid _type" do
      index_static
      by_file = index_rows.to_h { |r| [r[:file], r[:id].to_hash["_type"]] }
      expect(by_file["static/jcgm/200-2012.yaml"]).to eq "pubid:jcgm:guide"
      expect(by_file["static/jcgm/gum-6-2020.yaml"]).to eq "pubid:jcgm:gum-guide"
      expect(by_file["static/jcgm/gum.yaml"]).to eq "pubid:jcgm:guide"
      expect(by_file["static/jcgm/200-2008-corr.yaml"]).to eq "pubid:jcgm:corrigendum"
    end

    it "guards the index: a docnumber pubid cannot parse is skipped, not indexed" do
      subject.add_to_index "NOT A JCGM ID!!", "static/jcgm/bogus.yaml"
      subject.index.save
      expect(index_rows.map { |r| r[:file] }).not_to include("static/jcgm/bogus.yaml")
    end
  end
end
