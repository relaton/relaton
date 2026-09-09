require "relaton/xsf"

RSpec.describe Relaton::Xsf::HitCollection do
  # Every example searches the offline index seeded by
  # spec/xsf/support/webmock.rb -- the whole published index, pubid-keyed.
  # HitCollection takes an identifier, not a string -- Bibliography.parse_ref
  # does that step. See bibliography_spec.rb for the reference forms.
  def files(pubid)
    described_class.new(pubid).search.map { |hit| hit.hit[:url].split("/").last }
  end

  def pubid(ref) = Relaton::Xsf::Bibliography.parse_ref(ref)

  context "index narrowing" do
    let(:index) { described_class.new(pubid("XEP 0001")).index }

    it "deserializes the rows into pubid identifiers" do
      expect(index.index).to all include(id: an_instance_of(Pubid::Xsf::Identifiers::Xep))
    end

    it "binary-searches by number instead of scanning the whole index" do
      pubid = Pubid::Xsf::Identifier.parse "XEP 0001"
      candidates = index.send(:candidates_by_number, pubid)
      expect(index.index.size).to be > 500
      expect(candidates.size).to eq 1
    end

    # Two published rows are pages rather than XEPs. pubid accepts them as the
    # literal numbers `README` and `xxxx`, so they are carried like any other
    # row -- and they must be, because one row Relaton::Index cannot rebuild
    # makes it discard the whole file and return an empty index.
    it "carries the two rows that are pages rather than XEPs" do
      rendered = index.index.map { |r| r[:id].to_s }
      expect(rendered).to include("XEP README", "XEP xxxx")
    end

    it "resolves them like any other reference" do
      expect(files(pubid("XEP README"))).to eq ["xep-readme.yaml"]
    end
  end

  context "lookup" do
    it "returns the row for an identifier" do
      expect(files(pubid("XEP 0001"))).to eq ["xep-0001.yaml"]
    end

    it "returns nothing for a document not in the index" do
      expect(files(pubid("XEP 9999"))).to be_empty
    end

    # Bibliography.parse_ref hands nil through when a reference cannot be
    # parsed, so the collection has to tolerate it rather than raise.
    it "returns nothing for a nil identifier" do
      expect(files(nil)).to be_empty
    end
  end
end
