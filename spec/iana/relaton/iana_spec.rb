# frozen_string_literal: true

RSpec.describe Relaton::Iana do
  # No index-download stubs here: the pubid-keyed index-v2 fixture is pooled in
  # `before(:suite)` (support/webmock.rb) and answers the consumer (`url:`)
  # lookup offline, exactly as every other pubid flavor's suite does.

  describe "the pubid index-v2 fixture" do
    let(:index) { iana_index_fixture }

    # Relaton cannot catch a stale index on its own: FileIO#id_supported?
    # returns early for a concrete subclass, and every IANA row is one, so a row
    # still keyed the pre-`number` way would deserialize with a nil number and
    # NO error — then bucket under "" and silently defeat the search. This is
    # the tripwire for that.
    it "deserializes every row to a Registry with a non-empty number" do
      rows = index.index
      expect(rows.size).to eq 3405
      expect(rows.map { |r| r[:id].class }.uniq)
        .to eq [::Pubid::Iana::Identifiers::Registry]
      expect(rows.select { |r| r[:id].root.number.to_s.empty? }).to be_empty
    end

    # `to_s(with_publisher: false)` is the bare slug that WAS the index-v1 key,
    # and relaton-data-iana's crawler derives index-v1 from these two fields.
    it "renders every row back to the index-v1 slug it came from" do
      drifted = index.index.reject do |r|
        id = r[:id]
        expected = id.sub_registry ? "#{id.number}/#{id.sub_registry}" : id.number
        id.to_s(with_publisher: false) == expected
      end
      expect(drifted).to be_empty
      expect(index.index.count { |r| r[:id].sub_registry }).to eq 2750
    end

    # The whole point of index-v2: `Type#search_candidates` only bsearches when
    # the id is a pubid AND FileIO marked the index sorted. If `number` were
    # empty again, all 3405 rows would land in one bucket.
    it "narrows the search by bsearch on the top-level slug" do
      pubid = ::Pubid::Iana::Identifier.parse "pcep"
      candidates = index.send :candidates_by_number, pubid
      expect(candidates.size).to be < 100
      expect(candidates.map { |r| r[:id].number }.uniq).to eq ["pcep"]
    end
  end

  it "has a version number" do
    expect(Relaton::VERSION).not_to be nil
  end

  it "returs grammar hash" do
    hash = Relaton::Iana.grammar_hash
    expect(hash).to be_instance_of String
    expect(hash.size).to eq 32
  end

  it "get document", vcr: "auto-response-parameters" do
    expect do
      bib = Relaton::Iana::Bibliography.get "IANA auto-response-parameters"
      xml = bib.to_xml bibdata: true
      file = "fixtures/auto-response-parameters.xml"
      File.write file, xml, encoding: "UTF-8" unless File.exist? file
      expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
        .sub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}(?=<\/fetched>)/, Date.today.to_s)
      schema = Jing.new "../../grammar/relaton-iana-compile.rng"
      errors = schema.validate file
      expect(errors).to eq []
    end.to output(
      include(
        "[relaton-iana] INFO: (IANA auto-response-parameters) Fetching from Relaton repository ...",
        "[relaton-iana] INFO: (IANA auto-response-parameters) Found: `IANA auto-response-parameters`",
      ),
    ).to_stderr_from_any_process
  end

  it "not found document" do
    expect do
      bib = Relaton::Iana::Bibliography.get "IANA Link Relation Types"
      expect(bib).to be_nil
    end.to output(/\[relaton-iana\] INFO: \(IANA Link Relation Types\) Not found\./).to_stderr_from_any_process
  end
end
