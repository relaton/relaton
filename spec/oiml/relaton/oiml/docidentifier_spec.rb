# OIML sometimes co-publishes a document jointly with another SDO (ISO
# confirmed so far), printed as two full identifiers joined by "|":
#
#   ISO 4064-1:2024|OIML R 49-1:2024
#
# pubid models this as Pubid::Oiml::Identifiers::DualPublished (pubid#437),
# which wraps both sides but only delegates #root/#code/#type/#stage/
# #iteration/#publisher/the mr_* hooks to whichever side is OIML. A direct
# mutation of #date=/#part= on the wrapper itself is a silent no-op (it never
# reaches either side); only the generic, immutable #exclude correctly
# recurses into both sides. relaton#180 closes that gap by rebuilding
# `content` through #exclude instead of mutating `@pubid` in place.
RSpec.describe Relaton::Oiml::Docidentifier do
  it "parses a dual-published reference with the external id printed first" do
    docid = described_class.new(content: "ISO 4064-1:2024|OIML R 49-1:2024")
    expect(docid.content).to eq "ISO 4064-1:2024|OIML R 49-1:2024"
    expect(docid.pubid).to be_a Pubid::Oiml::Identifiers::DualPublished
    expect(docid.pubid.oiml_identifier.to_s).to eq "OIML R 49-1:2024"
    expect(docid.pubid.external_identifier.to_s).to eq "ISO 4064-1:2024"
  end

  it "parses a dual-published reference with the OIML id printed first" do
    docid = described_class.new(content: "OIML R 49-1:2024|ISO 4064-1:2024")
    expect(docid.pubid.oiml_identifier.to_s).to eq "OIML R 49-1:2024"
    expect(docid.pubid.external_identifier.to_s).to eq "ISO 4064-1:2024"
  end

  describe "#remove_date!" do
    it "undates both sides of a dual-published identifier" do
      docid = described_class.new(content: "ISO 4064-1:2024|OIML R 49-1:2024")
      docid.remove_date!
      expect(docid.content).to eq "ISO 4064-1|OIML R 49-1"
      # Guards against `content=`'s `rescue StandardError; @pubid = nil`
      # silently swallowing a future re-parse regression in this exact path.
      expect(docid.pubid).to be_a Pubid::Oiml::Identifiers::DualPublished
      expect(docid.pubid.oiml_identifier.to_s).to eq "OIML R 49-1"
      expect(docid.pubid.external_identifier.to_s).to eq "ISO 4064-1"
    end

    it "still undates a plain identifier (regression guard)" do
      docid = described_class.new(content: "OIML R 138:2007 (E)")
      docid.remove_date!
      expect(docid.content).to eq "OIML R 138 (E)"
    end
  end

  describe "#remove_part!" do
    it "clears the part on both sides of a dual-published identifier" do
      docid = described_class.new(content: "ISO 4064-1:2024|OIML R 49-1:2024")
      docid.remove_part!
      expect(docid.content).to eq "ISO 4064:2024|OIML R 49:2024"
      expect(docid.pubid).to be_a Pubid::Oiml::Identifiers::DualPublished
      expect(docid.pubid.oiml_identifier.to_s).to eq "OIML R 49:2024"
      expect(docid.pubid.external_identifier.to_s).to eq "ISO 4064:2024"
    end

    it "still clears the part on a plain identifier (regression guard)" do
      docid = described_class.new(content: "OIML R 137-1:2012 (F)")
      docid.remove_part!
      expect(docid.content).to eq "OIML R 137:2012 (F)"
    end
  end

  describe "#to_all_parts!" do
    it "does not raise for a dual-published identifier" do
      docid = described_class.new(content: "ISO 4064-1:2024|OIML R 49-1:2024")
      expect { docid.to_all_parts! }.not_to raise_error
    end
  end
end
