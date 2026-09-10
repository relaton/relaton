# frozen_string_literal: true

describe Relaton::Bsi::Hit do
  def hit(code) = described_class.new({ code: code }, nil)

  describe "#pubid" do
    it "parses a catalogue code" do
      expect(hit("BS EN ISO 8848:2021").pubid).to be_a Pubid::Bsi::Identifier
    end

    # The Algolia catalogue carries codes pubid cannot parse (this one is a
    # real hit for "BS 381C"). One such row must not abort the search, so
    # the hit side yields nil while a malformed query raises.
    it "is nil for a catalogue code pubid cannot parse" do
      expect(hit("BS 381C SET:1996 (R2002)").pubid).to be_nil
    end
  end
end
