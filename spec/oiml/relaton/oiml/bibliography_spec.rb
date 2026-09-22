RSpec.describe Relaton::Oiml::Bibliography do
  # The row a reference resolves to, from an index built in memory. It does not
  # use `from_hash`, so it runs despite the combined-bundle regression that
  # skips the "get document" examples in `oiml_spec.rb`.
  def row_for(ref, year = nil, rows:)
    index = Relaton::Index::Type.new :oiml
    index.instance_variable_set :@index, rows.map { |id, file| { id: Pubid::Oiml.parse(id), file: file } }
    allow(described_class).to receive(:index).and_return(index)
    described_class.send(:best_row, Pubid::Oiml.parse(ref), year)&.fetch(:file)
  end

  context "a Bulletin" do
    let(:rows) do
      { "OIML Bulletin 1960" => "volume.yaml",
        "OIML Bulletin 1960-03-01" => "article-1.yaml",
        "OIML Bulletin 1960-03-02" => "article-2.yaml",
        "OIML Bulletin 1961-03-01" => "next-year.yaml" }
    end

    # The year is part of a Bulletin's locator, so every article of one year
    # used to reduce to the same stem, and a search took one of them.
    it "resolves an article to its own row" do
      expect(row_for("OIML Bulletin 1960-03-01", rows: rows)).to eq "article-1.yaml"
      expect(row_for("OIML Bulletin 1960-03-02", rows: rows)).to eq "article-2.yaml"
    end

    it "resolves a volume to the volume row, not an article" do
      expect(row_for("OIML Bulletin 1960", rows: rows)).to eq "volume.yaml"
    end
  end

  # The pairs below are where pubid's subset match `===` disagrees with this
  # flavor over the full data index, so the flavor keeps its own match.
  context "where the subset match would disagree" do
    let(:rows) do
      { "OIML R 126:2015 Errata (E)" => "errata-e.yaml",
        "OIML R 126:2015 Errata" => "errata.yaml",
        "OIML R 137-1-2:2012 (F)" => "r137-1-2-f.yaml",
        "OIML R 102:1995 Annex B-C" => "r102-annex.yaml" }
    end

    it "does not answer a language-less reference with a translation" do
      expect(row_for("OIML R 126:2015 Errata", rows: rows)).to eq "errata.yaml"
    end

    it "does not answer a part with its subpart" do
      expect(row_for("OIML R 137-1 (F)", rows: rows)).to be_nil
    end

    it "finds a dated annex from an undated reference" do
      expect(row_for("OIML R 102 Annex B-C", rows: rows)).to eq "r102-annex.yaml"
    end
  end

  context "a Recommendation" do
    let(:rows) do
      { "OIML R 138:2007 (E)" => "r138-2007-e.yaml",
        "OIML R 138:2007" => "r138-2007.yaml",
        "OIML R 138-Amend:2009" => "r138-amend.yaml",
        "OIML R 138:2001" => "r138-2001.yaml" }
    end

    it "resolves an undated reference to the latest language-less edition" do
      expect(row_for("OIML R 138", rows: rows)).to eq "r138-2007.yaml"
    end

    it "resolves a language to that translation" do
      expect(row_for("OIML R 138:2007 (E)", rows: rows)).to eq "r138-2007-e.yaml"
    end

    it "does not answer the base reference with its amendment" do
      expect(row_for("OIML R 138-Amend", rows: rows)).to eq "r138-amend.yaml"
      expect(row_for("OIML R 138:2009", rows: rows)).to be_nil
    end

    it "pins the edition that the year argument names" do
      expect(row_for("OIML R 138", "2001", rows: rows)).to eq "r138-2001.yaml"
    end
  end
end
