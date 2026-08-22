# frozen_string_literal: true

RSpec.describe Relaton::Iana::Bibliography do
  # The pooled fixture is the pubid-keyed index-v2 (spec/iana/support/webmock.rb),
  # so these examples exercise the real search path offline: `#search` is stubbed
  # short of the HTTP fetch and asserted on the row it picked.
  def row_for(ref)
    index = described_class.send :index
    pubid = described_class.send :parse_ref, ref
    return nil unless pubid

    index.search(pubid) { |r| described_class.send(:pubid_match?, r[:id], pubid) }.first
  end

  describe "index lookup" do
    it "resolves a top-level registry to the top-level row, not a sub-registry" do
      row = row_for "IANA _6lowpan-parameters"
      expect(row[:file]).to eq "data/_6lowpan-parameters.yaml"
      expect(row[:id].number).to eq "_6lowpan-parameters"
      expect(row[:id].sub_registry).to be_nil
    end

    it "resolves a sub-registry" do
      row = row_for "IANA _6lowpan-parameters/lowpan_nhc"
      expect(row[:file]).to eq "data/_6lowpan-parameters-lowpan_nhc.yaml"
      expect(row[:id].sub_registry).to eq "lowpan_nhc"
    end

    it "resolves a bare slug with no `IANA ` prefix" do
      row = row_for "_6lowpan-parameters/lowpan_nhc"
      expect(row[:file]).to eq "data/_6lowpan-parameters-lowpan_nhc.yaml"
    end

    it "does not resolve a sub-registry slug given on its own" do
      # index-v1 matched ids by substring, so the bare sub-registry slug hit the
      # `_6lowpan-parameters/lowpan_nhc` row. A pubid index matches exactly.
      expect(row_for("IANA lowpan_nhc")).to be_nil
    end
  end

  describe "#search" do
    it "returns nil for an unparseable reference instead of raising" do
      expect { expect(described_class.search("IANA Link Relation Types")).to be_nil }
        .to output(/Failed to parse/).to_stderr_from_any_process
    end

    it "accepts a Pubid::Iana identifier as the reference" do
      pubid = ::Pubid::Iana::Identifier.parse "_6lowpan-parameters"
      expect(described_class).to receive(:fetch_row).with(
        hash_including(file: "data/_6lowpan-parameters.yaml"),
      ).and_return(:item)
      expect(described_class.search(pubid)).to eq :item
    end

    it "raise RequestError" do
      expect(Relaton::Index).to receive(:find_or_create).and_raise(SocketError)
      expect { described_class.get "ref" }.to raise_error Relaton::RequestError
    end
  end

  describe "#pubid_match?" do
    let(:query) { ::Pubid::Iana::Identifier.parse "sip-parameters" }

    it "matches an equal identifier" do
      row_id = ::Pubid::Iana::Identifier.parse "sip-parameters"
      expect(described_class.send(:pubid_match?, row_id, query)).to be true
    end

    it "does not match a sub-registry of the same registry" do
      row_id = ::Pubid::Iana::Identifier.parse "sip-parameters/sip-parameters-13"
      expect(described_class.send(:pubid_match?, row_id, query)).to be false
    end
  end
end
