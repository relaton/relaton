# frozen_string_literal: true

RSpec.describe Relaton::Adobe::Docidentifier do
  it "parses a tech-note content string into a Pubid::Adobe identifier" do
    did = described_class.new(content: "Adobe Technical Note #5014")
    expect(did.pubid).to be_a(::Pubid::Adobe::Identifiers::TechNote)
    expect(did.pubid.number).to eq "5014"
  end

  it "parses the ATN alias into the same tech-note identifier" do
    did = described_class.new(content: "ATN5014")
    expect(did.pubid).to be_a(::Pubid::Adobe::Identifiers::TechNote)
    expect(did.pubid.number).to eq "5014"
    expect(did.pubid.to_s).to eq "Adobe TN 5014"
  end

  it "parses a publication content string into a Publication identifier" do
    did = described_class.new(content: "Adobe Publication adobe-japan1-7")
    expect(did.pubid).to be_a(::Pubid::Adobe::Identifiers::Publication)
    expect(did.pubid.slug).to eq "adobe-japan1"
    expect(did.pubid.version).to eq "7"
  end

  it "soft-parses: leaves pubid nil (and keeps content) for an unparseable id" do
    did = described_class.new(content: "Adobe Glyph List")
    expect(did.pubid).to be_nil
    expect(did.content).to eq "Adobe Glyph List"
  end

  it "accepts a pubid directly and derives content from it" do
    pubid = ::Pubid::Adobe.parse("Adobe Technical Note #5014")
    did = described_class.new(pubid: pubid)
    expect(did.content).to eq "Adobe TN 5014"
    expect(did.pubid).to eq pubid
  end

  it "implements the base mutation hooks without raising (Adobe has no date/part)" do
    did = described_class.new(content: "Adobe Technical Note #5014")
    expect { did.remove_part! }.not_to raise_error
    expect { did.remove_date! }.not_to raise_error
    expect { did.to_all_parts! }.not_to raise_error
    # rendering is unchanged — Adobe ids carry no part/date/all-parts component
    expect(did.content).to eq "Adobe TN 5014"
  end
end
