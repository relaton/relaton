# frozen_string_literal: true

# `pubid/ietf` reopens `module Pubid` and extends `Pubid::PrefixesSupport`, so the
# base gem has to be loaded first — requiring the flavor alone NameErrors.
require "pubid"
require "pubid/ietf"

# The contract `Relaton::Ietf` relies on for its index to move from the legacy
# string `:id` to the structured pubid hash (relaton#109).
#
# Why this is a spec and not a note: an index built with `pubid_class:` is
# all-or-nothing. `Relaton::Index::FileIO#deserialize_id` raises
# `InvalidIndexError` on the *first* id it cannot parse, and `#load_index` then
# rejects the entire index, re-downloads it, and rejects it again. A single
# unparseable row out of 176,862 means no consumer can use the IETF index at all.
# So "does pubid still hold up its end?" has to be a test result, not a judgement
# call — and it has to stay one, because every id below is a shape pubid got
# wrong at least once.
#
# All three groups were pubid gaps, closed 2026-08-20 (the asks are recorded in
# /work/HANDOFFS/metanorma__pubid__ietf-index-readiness.md). Verified at the time
# against the full published corpus — 176,862 identifiers across
# relaton-data-{rfcs,rfcsubseries,ids}, zero parse failures and zero round-trip
# failures. These examples are the representative shapes; keep them green.
describe "Pubid::Ietf contract for the unified IETF index" do
  # Round-trip through the exact path Relaton::Index takes: `to_hash` on save,
  # `from_hash` on read (FileIO#deserialize_id), compared by rendered form.
  #
  # Round-tripping matters more than it looks: `FileIO#id_supported?` *skips* its
  # to_hash/from_hash check for any id that resolves to a concrete subclass, and
  # every Pubid::Ietf id does. So relaton itself never validates this — a lossy
  # round-trip would sail through and produce silently wrong lookups.
  def round_trip(str)
    id = Pubid::Ietf::Identifier.parse(str)
    Pubid::Ietf::Identifier.from_hash(id.to_hash)
  end

  context "identifier forms the published corpus contains" do
    # The first four are the bulk of the corpus. The last four are draft slugs
    # that the original grammar rejected: its `draft_rest` admitted neither `.`
    # (21 ids) nor uppercase (29 ids).
    ["RFC 3986", "STD 66", "BCP 9", "FYI 1",
     "draft-ietf-quic-transport-34", "draft-ietf-quic-transport",
     "draft-ietf-pilc-2.5g3g-12", "draft-chapin-clnp-ISO8473-00"].each do |str|
      it "parses and round-trips #{str}" do
        expect(round_trip(str).to_s).to eq str
      end
    end
  end

  # The RFC 3986 <-> STD 66 cross-reference rows are the headline of #109, and
  # their source is the rfc-index `<is-also>` element, which emits the
  # zero-padded form. Relaton must never normalise these itself — #109 requires
  # ids to come from pubid render, never string surgery — so the padding has to
  # be pubid's problem, and staying that way is what this guards.
  context "zero-padded sub-series ids from rfc-index <is-also>" do
    { "STD0066" => "STD 66", "BCP0009" => "BCP 9",
      "FYI0036" => "FYI 36" }.each do |padded, canonical|
      it "renders #{padded} as #{canonical}" do
        expect(Pubid::Ietf::Identifier.parse(padded).to_s).to eq canonical
      end
    end
  end

  # Relaton::Index narrows search candidates by `id.root.number.to_s` before
  # matching (Type#candidates_by_number, and the sorts in FileIO that keep the
  # bsearch valid). Internet-Drafts originally stored the slug in `name` and left
  # `number` nil, which keyed all 166,740 draft rows to "" — one bucket, so the
  # bsearch bought nothing. Keying on the slug yields 43,564 buckets, mean 3.83
  # rows, max 101.
  #
  # Note this only bites once lookups pass parsed identifiers: `search_candidates`
  # narrows only for non-String queries, and `Scraper` still passes strings. That
  # is precisely why it needs a spec — until the flavor switches, nothing else
  # would notice a regression here, and after it switches the symptom is silent
  # (slower, never wrong).
  context "narrowing key" do
    it "gives a draft its versionless slug, shared across its versions" do
      versioned = Pubid::Ietf::Identifier.parse("draft-ietf-quic-transport-34")
      aggregate = Pubid::Ietf::Identifier.parse("draft-ietf-quic-transport")

      expect(versioned.root.number.to_s).to eq "draft-ietf-quic-transport"
      expect(aggregate.root.number.to_s).to eq versioned.root.number.to_s
    end

    it "is never empty, for any family in the corpus" do
      %w[RFC\ 3986 STD\ 66 BCP\ 9 FYI\ 1
         draft-ietf-quic-transport-34 draft-ietf-quic-transport].each do |str|
        key = Pubid::Ietf::Identifier.parse(str).root.number.to_s
        expect(key).not_to be_empty, "#{str} keys to \"\" — bsearch collapses"
      end
    end
  end
end
