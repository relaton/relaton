require "relaton/xsf"

RSpec.describe Relaton::Xsf::HitCollection do
  # Every example searches the offline index seeded by
  # spec/xsf/support/webmock.rb -- the whole published index, pubid-keyed.
  def files(ref)
    described_class.new(ref).search.map { |hit| hit.hit[:url].split("/").last }
  end

  context "index narrowing" do
    let(:index) { described_class.new("XEP 0001").index }

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
      expect(files("XEP README")).to eq ["xep-readme.yaml"]
    end
  end

  context "reference forms" do
    it "resolves the canonical form" do
      expect(files("XEP 0001")).to eq ["xep-0001.yaml"]
    end

    it "resolves the hyphenated form xmpp.org uses" do
      # New support: the old substring match compared against "XEP 0001", so a
      # hyphen never matched.
      expect(files("XEP-0001")).to eq ["xep-0001.yaml"]
    end

    it "resolves a bare number, which the substring match used to allow" do
      expect(files("0001")).to eq ["xep-0001.yaml"]
    end

    it "is case-insensitive on the publisher token" do
      expect(files("xep 0001")).to eq ["xep-0001.yaml"]
    end
  end

  context "exactness" do
    # The old `index.search(ref)` matched a SUBSTRING of the rendered id, so a
    # bare "001" answered with 11 documents and `Bibliography#get` took the
    # first. Matching is exact now.
    it "does not answer a truncated number with every document that contains it" do
      expect(files("001")).to be_empty
    end

    it "returns nothing for a document not in the index" do
      expect(files("XEP 9999")).to be_empty
    end

    it "returns nothing for an unparseable reference" do
      expect(Relaton.logger_pool).to receive(:warn).with(/Failed to parse pubid/, any_args)
      expect(files("not an identifier")).to be_empty
    end
  end
end
