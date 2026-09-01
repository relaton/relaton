# frozen_string_literal: true

# Self-contained unit specs for the 3GPP index-fixture builder. Only the pure
# selection/conversion halves are covered here; the download and zip write are
# exercised by running the task itself.
require_relative "../../tasks/index_fixture_3gpp"

RSpec.describe IndexFixture3gpp do
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

  describe ".curate" do
    it "keeps only the grouped rows, in the published order" do
      rows = [
        { id: "TS 38.331:REL-19/19.0.0", file: "a.yaml" },
        { id: "TS 23.207:REL-4/1.0.0",   file: "b.yaml" },
        { id: "TR 00.01U:UMTS/3.0.0",    file: "c.yaml" },
        { id: "TS 23.2071:REL-4/4.0.0",  file: "d.yaml" },
      ]
      expect(described_class.curate(rows).map { |r| r[:file] })
        .to eq %w[b.yaml c.yaml]
    end
  end

  describe ".to_pubid_rows" do
    it "replaces the string id with the pubid hash and keeps the file" do
      rows = [{ id: "TS 29.198-04-1:REL-5/5.0.0", file: "x.yaml" }]
      expect(described_class.to_pubid_rows(rows)).to eq [
        { id: { "_type" => "pubid:3gpp:technical-specification",
                "number" => "29.198", "parts" => %w[04 1],
                "release" => "REL-5", "version" => "5.0.0" },
          file: "x.yaml" },
      ]
    end

    it "omits the segments a row does not carry" do
      rows = [{ id: "TS 29.215/2.0.0", file: "y.yaml" }]
      expect(described_class.to_pubid_rows(rows).first[:id])
        .to eq("_type" => "pubid:3gpp:technical-specification",
               "number" => "29.215", "version" => "2.0.0")
    end

    # A fixture the consumer would reject is worse than no fixture:
    # Relaton::Index throws out the WHOLE index on one bad row.
    it "raises rather than writing a row pubid cannot parse" do
      rows = [{ id: "not an identifier", file: "z.yaml" }]
      expect { described_class.to_pubid_rows(rows) }
        .to raise_error Parslet::ParseFailed
    end
  end
end
