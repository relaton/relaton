# frozen_string_literal: true

describe Relaton::Jis::Docidentifier do
  subject do
    described_class.new(
      content: "JIS A 1301-1:2020", type: "JIS", primary: true,
    )
  end

  def docid(content)
    described_class.new content: content, type: "JIS", primary: true
  end

  it "#remove_part!" do
    subject.remove_part!
    expect(subject.content).to eq "JIS A 1301:2020"
  end

  it "#remove_date!" do
    subject.remove_date!
    expect(subject.content).to eq "JIS A 1301-1"
  end

  it "#to_all_parts!" do
    subject.to_all_parts!
    expect(subject.content).to eq "JIS A 1301 (all parts)"
  end

  describe "#pubid" do
    it "parses the content" do
      expect(subject.pubid).to be_a Pubid::Jis::Identifier
    end

    it "is flagged as all parts after #to_all_parts!" do
      subject.to_all_parts!
      expect(subject.pubid.all_parts).to be true
    end

    it "follows a content change" do
      subject.pubid
      subject.content = "JIS X 0208:1997"
      expect(subject.pubid.number).to eq "0208"
    end
  end

  context "with a multi-level part" do
    subject { docid "JIS C 0364-2-21:1999" }

    it "#remove_part! removes every part level" do
      subject.remove_part!
      expect(subject.content).to eq "JIS C 0364:1999"
    end

    it "#to_all_parts! names the whole document" do
      subject.to_all_parts!
      expect(subject.content).to eq "JIS C 0364 (all parts)"
    end
  end

  context "with a reaffirmation marker" do
    it "#remove_date! removes the marker with the year" do
      subject = docid "JIS C 9901:2019R"
      subject.remove_date!
      expect(subject.content).to eq "JIS C 9901"
    end
  end

  context "without the JIS publisher" do
    it "#remove_date! adds no publisher" do
      subject = docid "TR Z 0010:2008"
      subject.remove_date!
      expect(subject.content).to eq "TR Z 0010"
    end
  end

  context "with a supplement" do
    subject { docid "JIS B 3700-101:1996/CORRIGENDUM 1:2002" }

    it "#remove_date! removes only the date of the base" do
      subject.remove_date!
      expect(subject.content).to eq "JIS B 3700-101/CORRIGENDUM 1:2002"
    end

    it "#remove_part! removes the part of the base" do
      subject.remove_part!
      expect(subject.content).to eq "JIS B 3700:1996/CORRIGENDUM 1:2002"
    end

    it "#to_all_parts! removes the part and date of the base" do
      subject.to_all_parts!
      expect(subject.content).to eq "JIS B 3700/CORRIGENDUM 1:2002 (all parts)"
    end

    it "does not change a pubid that was read before the mutation" do
      before = subject.pubid
      subject.remove_date!
      expect(before.base.year).to eq 1996
    end

    it "renders the pubid canonical spelling" do
      subject = docid "JIS A 0206:2013/AMENDMENT 1:2023"
      subject.remove_date!
      expect(subject.content).to eq "JIS A 0206/AMD 1:2023"
    end
  end

  context "when no part or date" do
    subject do
      described_class.new(content: "JIS A 1301", type: "JIS", primary: true)
    end

    it "#remove_part! is a no-op" do
      subject.remove_part!
      expect(subject.content).to eq "JIS A 1301"
    end

    it "#remove_date! is a no-op" do
      subject.remove_date!
      expect(subject.content).to eq "JIS A 1301"
    end
  end

  context "when the content does not parse" do
    subject { docid "JIS-1301-1:2020" }

    it "#pubid is nil" do
      expect(subject.pubid).to be_nil
    end

    it "#remove_part! is a no-op" do
      subject.remove_part!
      expect(subject.content).to eq "JIS-1301-1:2020"
    end

    it "#remove_date! is a no-op" do
      subject.remove_date!
      expect(subject.content).to eq "JIS-1301-1:2020"
    end

    it "#to_all_parts! is a no-op" do
      subject.to_all_parts!
      expect(subject.content).to eq "JIS-1301-1:2020"
    end
  end
end
