require "relaton/ogc"

RSpec.describe Relaton::Ogc::HitCollection do
  # Every example searches the offline index seeded by
  # spec/ogc/support/webmock.rb — the whole published index, pubid-keyed.
  subject(:collection) { described_class.new("") }

  def match(ref)
    collection.send(:best_match, ref)&.fetch(:file)
  end

  context "index narrowing" do
    let(:index) { collection.send(:index) }

    it "deserializes the rows into pubid identifiers" do
      expect(index.index).to all include(id: an_instance_of(Pubid::Ogc::Identifiers::Document))
    end

    it "binary-searches by number instead of scanning the whole index" do
      pubid = Pubid::Ogc::Identifier.parse "12-128"
      candidates = index.send(:candidates_by_number, pubid)
      expect(index.index.size).to be > 1000
      expect(candidates.map { |r| r[:id].number }.uniq).to eq ["128"]
      expect(candidates.size).to be < 30
    end

    it "keeps years that reuse a number in one bucket, and apart in the result" do
      # The bsearch key is the <nnn> field alone, so `05-015` and `26-015`
      # share bucket "015"; `year` is what separates them.
      pubid = Pubid::Ogc::Identifier.parse "05-015"
      years = index.send(:candidates_by_number, pubid).map { |r| r[:id].year }
      expect(years.uniq.size).to be > 1
      expect(match("05-015")).to eq "data/05-015.yaml"
      expect(match("26-015r1")).to eq "data/26-015R1.yaml"
    end
  end

  context "row selection" do
    it "returns the latest revision for a bare reference" do
      # 12-128 is published as r10, r11, r12, r12a, r14, r15, r17, r18, r19.
      expect(match("12-128")).to eq "data/12-128R19.yaml"
    end

    it "does not order revisions as text" do
      # r2 beats r19 lexicographically; the numeric key must not.
      expect(match("12-128")).not_to eq "data/12-128R10.yaml"
    end

    it "honours a revision the reference asks for" do
      expect(match("12-128r14")).to eq "data/12-128R14.yaml"
      expect(match("12-128r12a")).to eq "data/12-128R12A.yaml"
    end

    it "accepts the OGC publisher token" do
      expect(match("OGC 12-128r14")).to eq "data/12-128R14.yaml"
    end

    it "accepts an uppercase revision, which pubid canonicalizes" do
      expect(match("11-038R2")).to eq "data/11-038R2.yaml"
      expect(match("11-038r2")).to eq "data/11-038R2.yaml"
    end

    it "finds a document that has only one revision" do
      expect(match("20-001r2")).to eq "data/20-001R2_.yaml"
    end

    it "returns nil for a document not in the index" do
      expect(match("99-999")).to be_nil
    end

    it "falls back to a substring scan when pubid cannot parse the reference" do
      # `Util.warn` reaches the logger through `method_missing`, so the
      # expectation goes on the pool rather than on `Util` (a partial double
      # there would be shadowed by the private `Kernel#warn`).
      expect(Relaton.logger_pool).to receive(:warn).with(/Failed to parse pubid/, any_args)
      expect(match("not an identifier")).to be_nil
    end
  end
end
