describe Relaton::Iso::HitCollection do
  # Materialise a row the way Relaton::Index does: serialise a parsed id to the
  # hash the index stores, then read it back via from_hash. The stored hash
  # carries `_type`, so from_hash rebuilds the concrete subclass — exactly as
  # production does. (A hand-built flat hash omits `_type` and only resolves to
  # a bare Identifier, whose `==` never matches a parsed id.)
  def index_id(ref)
    ::Pubid::Iso::Identifier.from_hash(::Pubid::Iso::Identifier.parse(ref).to_hash)
  end

  let(:hit1) { Relaton::Iso::Hit.new({ id: ::Pubid::Iso::Identifier.parse("ISO 19115-1:2014") }) }
  let(:hit2) { Relaton::Iso::Hit.new({ id: ::Pubid::Iso::Identifier.parse("ISO 19115-2:2015") }) }

  let(:ref) { ::Pubid::Iso::Identifier.parse "ISO 19115-1:2014" }
  subject { described_class.new ref }

  describe "#ref_pubid_no_year" do
    it "returns pubid without year" do
      expect(subject.ref_pubid_no_year.to_s).to eq "ISO 19115-1"
    end
  end

  describe "#ref_pubid_excluded" do
    it "returns pubid with excluded parts" do
      expect(subject.ref_pubid_excluded.to_s).to eq "ISO 19115-1"
    end
  end

  describe "#find" do
    # Production index rows are always deserialized into Pubid::Identifier by
    # Relaton::Index (via the `pubid_class`), so mirror that here. Two part-1
    # rows (one materialised via from_hash, one via parse) exercise that find
    # keeps every matching row when not querying all parts.
    let(:index) do
      idx = Relaton::Index::Type.new :iso
      idx.instance_variable_set :@index, [
        { id: index_id("ISO 19115-1:2014") },
        { id: index_id("ISO 19115-2:2015") },
        { id: index_id("ISO 19115-3:2016") },
        { id: ::Pubid::Iso::Identifier.parse("ISO 19115-1:2014") },
      ]
      idx
    end

    before { expect(subject).to receive(:index).and_return index }

    it "finds all rows matching the ref" do
      expect(subject.find).to be_a described_class
      expect(subject.size).to eq 2
      expect(subject.first).to be_a Relaton::Iso::Hit
    end

    it "fing all parts & reverse sort by pubid" do
      ref.all_parts = true
      expect(subject.find.size).to eq 3
      expect(subject.first.pubid.to_s).to eq "ISO 19115-3:2016"
    end
  end

  describe "#pubid_match?" do
    it "exclude year" do
      expect(subject.pubid_match?(index_id("ISO 19115-1"))).to be true
    end

    it "exclude edition" do
      cand = index_id("ISO 19115-1:2014")
      cand.edition = ::Pubid::Components::Edition.new(number: "2")
      expect(subject.pubid_match?(cand)).to be true
    end
  end

  describe "#normalize_compound_part" do
    # The v1-generated index stores a compound part such as "5-1-3" whole in a
    # single Code (subpart nil), the way Relaton::Index materialises rows. A
    # parsed query splits it, so the candidate must be re-split before
    # comparison. The Code component exposes its number via `value`, not
    # `number`.
    it "splits a compound part value on the first dash" do
      cand = ::Pubid::Iso::Identifier.parse "ISO 19115"
      cand.part = ::Pubid::Iso::Components::Code.new(value: "5-1-3")
      result = subject.normalize_compound_part cand
      expect(result.part.value).to eq "5"
      expect(result.subpart.value).to eq "1-3"
    end

    it "leaves a simple (dash-free) part unchanged" do
      cand = ::Pubid::Iso::Identifier.parse "ISO 19115-2"
      result = subject.normalize_compound_part cand
      expect(result.part.value).to eq "2"
      expect(result.subpart).to be_nil
    end

    it "leaves an already-split part (subpart present) unchanged" do
      cand = ::Pubid::Iso::Identifier.parse "ISO 19115"
      cand.part = ::Pubid::Iso::Components::Code.new(value: "5-1")
      cand.subpart = ::Pubid::Iso::Components::Code.new(value: "3")
      result = subject.normalize_compound_part cand
      expect(result.part.value).to eq "5-1"
      expect(result.subpart.value).to eq "3"
    end
  end

  describe "#excludings" do
    it "returns excluded parts" do
      expect(subject.excludings).to eq %i[year stage iteration]
    end

    it "returns excluded parts with all_parts" do
      ref.all_parts = true
      expect(subject.excludings).to eq %i[year part stage iteration]
    end

    it "returns excluded parts when ref has no part" do
      subject.instance_variable_set :@ref, ::Pubid::Iso::Identifier.parse("ISO 19115")
      expect(subject.excludings).to eq %i[year part stage iteration]
    end
  end

  it "#index" do
    expect(subject.index).to be_a Relaton::Index::Type
  end

  describe "#fetch_doc" do
    it "no all_parts" do
      subject.instance_variable_set :@array, [hit1, hit2]
      expect(hit1).to receive(:item).and_return :doc
      expect(subject.fetch_doc).to be :doc
    end

    it "all_parts" do
      ref.all_parts = true
      subject.instance_variable_set :@array, [hit1, hit2]
      expect(subject).to receive(:to_all_parts).and_return :doc
      expect(subject.fetch_doc).to be :doc
    end

    it "all_parts with size 1" do
      subject.instance_variable_set :@array, [hit1]
      expect(hit1).to receive(:item).and_return :doc
      expect(subject.fetch_doc).to be :doc
    end
  end

  describe "#to_all_parts" do
    let(:hit_no_part) do
      Relaton::Iso::Hit.new({ id: ::Pubid::Iso::Identifier.parse("ISO 19115:2014") })
    end

    let(:docid) { Relaton::Iso::Docidentifier.new(content: hit1.pubid) }
    let(:relation_doc) { Relaton::Iso::ItemData.new(docidentifier: [docid]) }

    it "fetch first doc when no part" do
      subject.instance_variable_set :@array, [hit_no_part]
      expect(hit_no_part).to receive(:item).and_return :doc
      expect(subject.to_all_parts).to be :doc
    end

    it "fetch all parts" do
      subject.instance_variable_set :@array, [hit1, hit2]
      expect(hit1).to receive(:item).and_return relation_doc
      all_parts_item = subject.to_all_parts
      expect(all_parts_item).to be_a Relaton::Iso::ItemData
      expect(all_parts_item.relation.size).to eq 2
      expect(all_parts_item.relation[0]).to be_a Relaton::Iso::Relation
      expect(all_parts_item.relation[0].bibitem).to be_a Relaton::Iso::ItemData
      expect(all_parts_item.relation[0].bibitem.docidentifier.size).to eq 1
      expect(all_parts_item.relation[0].bibitem.docidentifier[0].to_s).to eq "ISO 19115-1:2014"
      expect(all_parts_item.relation[1].bibitem.docidentifier[0].to_s).to eq "ISO 19115-2:2015"
    end
  end
end
