# frozen_string_literal: true

# Self-contained unit specs for the 3GPP index-fixture builder. Only the pure
# selection halves are covered here; the download and zip write are exercised
# by running the task itself.
require_relative "../../tasks/index_fixture_3gpp"

RSpec.describe IndexFixture3gpp do
  # A published index-v2 row: the `:id` is a pubid hash, not a string.
  def row(id, file = "data/x.yaml")
    { id: id, file: file }
  end

  def ts(number, **rest)
    { "_type" => "pubid:3gpp:technical-specification",
      "number" => number }.merge(rest.transform_keys(&:to_s))
  end

  def tr(number, **rest)
    { "_type" => "pubid:3gpp:technical-report",
      "number" => number }.merge(rest.transform_keys(&:to_s))
  end

  describe ".keep?" do
    it "keeps a bare group id" do
      expect(described_class.keep?("TS 23.207")).to be true
    end

    it "keeps a row qualified by release and version" do
      expect(described_class.keep?("TS 23.207:REL-19/19.0.0")).to be true
    end

    it "keeps a row qualified by version alone" do
      expect(described_class.keep?("TS 29.215/2.0.0")).to be true
    end

    # The separator check is the whole point: a prefix match alone would drag
    # in a different document whose number merely starts the same way.
    it "rejects a longer number that merely starts with a group id" do
      expect(described_class.keep?("TS 23.2071:REL-4/4.0.0")).to be false
    end

    it "rejects a different part of the same base number" do
      expect(described_class.keep?("TS 29.198-04-2:REL-5/5.0.0")).to be false
    end

    it "rejects the same number under the other document type" do
      expect(described_class.keep?("TR 23.207:REL-4/4.0.0")).to be false
    end

    it "rejects a number that is not in any group" do
      expect(described_class.keep?("TS 38.331:REL-19/19.0.0")).to be false
    end
  end

  describe ".group_numbers" do
    # Parsed from the GROUPS keys so the two cannot drift apart. `29.198` comes
    # from the parts group `TS 29.198-04-1`, i.e. the base number, not the code.
    it "is the base document number of every group" do
      expect(described_class.group_numbers)
        .to match_array %w[23.207 05.05 04.08 29.198 00.01 29.215]
    end
  end

  describe ".render_id" do
    it "renders a published row back to its identifier string" do
      expect(described_class.render_id(
               ts("29.198", parts: %w[04 1], release: "REL-5", version: "5.0.0"),
             )).to eq "TS 29.198-04-1:REL-5/5.0.0"
    end

    it "renders a row that carries no release" do
      expect(described_class.render_id(ts("29.215", version: "2.0.0")))
        .to eq "TS 29.215/2.0.0"
    end

    # No publisher token: the rendered form must match the index id, which is
    # what `keep?` compares against.
    it "omits the 3GPP publisher token" do
      expect(described_class.render_id(ts("23.207", release: "REL-4")))
        .not_to start_with "3GPP"
    end
  end

  describe ".curate" do
    it "keeps only the grouped rows, in the published order" do
      rows = [
        row(ts("38.331", release: "REL-19", version: "19.0.0"), "a.yaml"),
        row(ts("23.207", release: "REL-4", version: "1.0.0"), "b.yaml"),
        row(tr("00.01", suffix: "U", release: "UMTS", version: "3.0.0"), "c.yaml"),
        row(ts("29.215", version: "2.0.0"), "d.yaml"),
      ]
      expect(described_class.curate(rows).map { |r| r[:file] })
        .to eq %w[b.yaml c.yaml d.yaml]
    end

    it "copies the rows verbatim rather than rebuilding them" do
      id = ts("23.207", release: "REL-19", version: "19.0.0")
      expect(described_class.curate([row(id)]).first[:id]).to equal id
    end

    # `TR 00.01U` is a group; `TR 00.01` (no suffix) is a different document
    # that shares the number, so the cheap number test alone must not keep it.
    it "rejects a row that shares a group number but not its code" do
      rows = [row(tr("00.01", release: "UMTS", version: "3.0.0"))]
      expect(described_class.curate(rows)).to be_empty
    end

    it "rejects the other document type on a group number" do
      rows = [row(tr("23.207", release: "REL-4", version: "1.0.0"))]
      expect(described_class.curate(rows)).to be_empty
    end

    # `curate` filters in two stages: a cheap `number` test, then the real
    # `keep?` on the rendered id. The cheap stage must be a strict SUPERSET of
    # the real one, or rows vanish silently. It holds because a rendered id is
    # "<TYPE> <code>" and `code` always begins with `number` — but that is an
    # invariant of the pubid renderer, not of this file, so pin it: every group
    # must survive its own pre-filter.
    it "never lets the number pre-filter drop a row keep? would accept" do
      require "pubid"
      described_class::GROUPS.each_key do |group|
        id = ::Pubid::Tgpp::Identifier.parse(group).to_hash
        expect(described_class.curate([row(id)]).size)
          .to eq(1), "pre-filter dropped #{group}"
      end
    end
  end

  describe ".ensure_v2!" do
    # A v1 index keys rows on a bare String. Writing those under the v2 name
    # would produce a fixture Relaton::Index rejects wholesale.
    it "refuses a v1 index" do
      rows = [{ id: "TS 23.207:REL-4/1.0.0", file: "b.yaml" }]
      expect { described_class.ensure_v2!(rows, "index-v1.zip") }
        .to raise_error(/v1 index/)
    end

    it "accepts a v2 index" do
      expect { described_class.ensure_v2!([row(ts("23.207"))], "x") }
        .not_to raise_error
    end

    it "accepts an empty index, which #build reports separately" do
      expect { described_class.ensure_v2!([], "x") }.not_to raise_error
    end
  end
end
