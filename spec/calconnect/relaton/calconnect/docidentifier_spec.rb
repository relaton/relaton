require "relaton/calconnect"

RSpec.describe Relaton::Calconnect::Docidentifier do
  subject { described_class.new content: "CC/DIR 10005:2019" }

  context "parsing" do
    it "keeps content verbatim" do
      expect(subject.content.to_s).to eq "CC/DIR 10005:2019"
    end

    it "parses content into a pubid" do
      expect(subject.pubid).to be_a ::Pubid::Calconnect::Identifier
      expect(subject.pubid.series).to eq "DIR"
      expect(subject.pubid.number).to eq "10005"
      expect(subject.pubid.date.year).to eq "2019"
    end

    it "parses a series-less id" do
      docid = described_class.new content: "CC 18011:2018"
      expect(docid.pubid.series).to be_nil
      expect(docid.pubid.number).to eq "18011"
    end

    it "parses an undated id" do
      docid = described_class.new content: "CC/DIR 10005"
      expect(docid.pubid.date).to be_nil
      expect(docid.pubid.to_s).to eq "CC/DIR 10005"
    end

    # An id pubid rejects is a data defect, so it is reported at ERROR. It must
    # not raise: an already-published record still has to deserialize.
    it "reports an unparseable id at ERROR and leaves pubid nil" do
      docid = nil
      expect do
        docid = described_class.new content: "not an identifier"
      end.to output(/ERROR: Failed to parse pubid `not an identifier`/).to_stderr_from_any_process
      expect(docid.pubid).to be_nil
      expect(docid.content.to_s).to eq "not an identifier"
    end

    it "leaves pubid nil for nil content" do
      expect(described_class.new.pubid).to be_nil
    end
  end

  context "mutators" do
    # CalConnect's only optional component. `Bib::ItemData#to_most_recent_reference`
    # broadcasts this to every docidentifier.
    it "#remove_date! drops the date and re-renders the content" do
      subject.remove_date!
      expect(subject.pubid.date).to be_nil
      expect(subject.content.to_s).to eq "CC/DIR 10005"
    end

    it "#remove_date! is a no-op when the id did not parse" do
      docid = nil
      expect { docid = described_class.new content: "not an identifier" }
        .to output(/ERROR/).to_stderr_from_any_process
      expect { docid.remove_date! }.not_to raise_error
      expect(docid.content.to_s).to eq "not an identifier"
    end

    # CalConnect models no part: `0812-1` and `0707.1` are one `number` token,
    # so there is nothing to strip.
    it "#remove_part! leaves a sub-numbered id alone" do
      docid = described_class.new content: "CC/A 0812-1:2008"
      docid.remove_part!
      expect(docid.content.to_s).to eq "CC/A 0812-1:2008"
    end

    it "#to_all_parts! is a no-op" do
      subject.to_all_parts!
      expect(subject.content.to_s).to eq "CC/DIR 10005:2019"
    end
  end
end
