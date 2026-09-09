require "relaton/calconnect"

# The runtime search path, which had no coverage at all before the index-v2
# migration — this file was an empty `describe` block.
RSpec.describe Relaton::Calconnect::HitCollection do
  def hits(ref, year = nil)
    described_class.new(ref, year).map { |h| h.hit[:id].to_s }
  end

  it "reads the pubid index-v2" do
    expect(Relaton::Index).to receive(:find_or_create).with(
      :CC,
      url: "#{described_class::GHURL}index-v2.zip",
      file: "index-v2.yaml",
      pubid_class: ::Pubid::Calconnect::Identifier,
    ).and_return(double("index", search: []))
    described_class.new "CC/DIR 10005"
  end

  it "deserializes rows into identifiers, not raw hashes" do
    row = described_class.new("CC/DIR 10005").first.hit
    expect(row[:id]).to be_a ::Pubid::Calconnect::Identifier
    expect(row[:file]).to eq "data/cc-dir-10005-2019.yaml"
  end

  context "narrowing" do
    # `Type#search_candidates` narrows only when the argument is not a String,
    # so passing the parsed pubid is what makes the bsearch engage at all.
    it "binary-searches by number instead of scanning the whole index" do
      index = CalconnectIndexFixture.index_type
      pubid = ::Pubid::Calconnect::Identifier.parse "CC/S 0601"
      candidates = index.send(:candidates_by_number, pubid)
      expect(index.index.size).to be > 150
      expect(candidates.map { |r| r[:id].number }.uniq).to eq ["0601"]
      expect(candidates.size).to be < 10
    end

    it "reaches every year of a document from an undated reference" do
      expect(hits("CC/S 0601")).to contain_exactly "CC/S 0601:2005", "CC/S 0601:2006"
    end

    it "matches a dated reference exactly" do
      expect(hits("CC/S 0601:2006")).to eq ["CC/S 0601:2006"]
    end

    # The series is the identifier's own attribute, never ignorable — it is
    # what keeps a committee draft and a working draft of one number apart.
    it "never crosses series" do
      expect(hits("CC/CD 51016")).to eq ["CC/CD 51016:2018"]
      expect(hits("CC/WD 51016")).to eq ["CC/WD 51016:2018"]
    end

    # A series-less id is its own form, not a wildcard.
    it "does not let a series-less reference match a seried row" do
      expect(hits("CC 36010")).to eq ["CC 36010:2026"]
    end

    it "matches an exact number, never a prefix" do
      expect(hits("CC/DIR 1000")).to be_empty
      expect(hits("CC/DIR 10005")).to eq ["CC/DIR 10005:2019"]
    end

    it "keeps a leading zero significant" do
      expect(hits("CC/A 1")).to be_empty
      expect(hits("CC/A 0001")).to eq ["CC/A 0001:2000"]
    end

    it "finds a sub-numbered document" do
      expect(hits("CC/A 0812-1")).to eq ["CC/A 0812-1:2008"]
    end

    it "finds a fully dated row from an undated reference" do
      expect(hits("CC/WD 51017")).to eq ["CC/WD 51017:2024-07-23"]
    end

    it "returns nothing for an unknown document" do
      expect(hits("CC/DIR 123456")).to be_empty
    end
  end

  context "ordering" do
    # The index is sorted by number, and rows sharing a number arrive in no
    # meaningful order, so the collection sorts newest-first itself. Without it
    # `Bibliography.get "CC/S 0601"` would answer with an arbitrary edition.
    it "puts the most recent date first" do
      expect(hits("CC/S 0601")).to eq ["CC/S 0601:2006", "CC/S 0601:2005"]
    end

    it "orders a three-way family newest-first" do
      expect(hits("CC/R 1011")).to eq ["CC/R 1011:2012", "CC/R 1011:2010"]
    end
  end

  context "an unparseable reference" do
    # It RAISES -- like ISO, ETSI and 3GPP, relaton lets the parse error
    # propagate so a caller can tell a malformed identifier from an absent
    # document. It is still never relabelled as a Relaton::RequestError:
    # Pubid::Errors::ParseError is a Parslet::ParseFailed, which is what
    # relaton-cli rescues to render "... is not a recognized standards
    # identifier".
    it "raises" do
      expect { described_class.new("not an identifier") }
        .to raise_error Pubid::Errors::ParseError
    end

    it "raises something relaton-cli knows how to render" do
      expect { described_class.new("not an identifier") }
        .to raise_error Parslet::ParseFailed
    end
  end
end
