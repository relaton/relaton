describe Relaton::Itu::Docidentifier do
  def docid(content, type: "ITU")
    described_class.new(type: type, content: content, primary: true)
  end

  it "inherits from Bib::Docidentifier" do
    expect(described_class).to be < Relaton::Bib::Docidentifier
  end

  describe "#pubid" do
    it "parses ITU content" do
      expect(docid("ITU-T L.163 (11/2018)").pubid).to be_a Pubid::Itu::Identifier
    end

    it "is nil for an ISO co-identifier" do
      expect(docid("ISO/IEC 14496-10", type: "ISO").pubid).to be_nil
    end

    it "follows a content change" do
      subject = docid("ITU-T L.163 (11/2018)")
      subject.pubid
      subject.content = "ITU-T G.711 (11/1988)"
      expect(subject.pubid.number).to eq "711"
    end
  end

  it "#remove_part! is a no-op, because an ITU-R -N is a revision" do
    subject = docid("ITU-R P.838-3 (03/2005)")
    subject.remove_part!
    expect(subject.content).to eq "ITU-R P.838-3 (03/2005)"
  end

  it "#to_all_parts! is a no-op" do
    subject = docid("ITU-R P.838-3 (03/2005)")
    subject.to_all_parts!
    expect(subject.content).to eq "ITU-R P.838-3 (03/2005)"
  end

  describe "#remove_date!" do
    it "removes month/year date" do
      subject = docid("ITU-T L.163 (11/2018)")
      subject.remove_date!
      expect(subject.content).to eq "ITU-T L.163"
    end

    it "removes the date from the pubid" do
      subject = docid("ITU-T L.163 (11/2018)")
      subject.remove_date!
      expect(subject.pubid.year).to be_nil
    end

    it "removes the dates of a supplement and of its base" do
      subject = docid("ITU-T H.264 (2005) Amd. 1 (06/2006)")
      subject.remove_date!
      expect(subject.content).to eq "ITU-T H.264 Amd. 1"
    end

    it "leaves identifier unchanged when no date present" do
      subject = docid("ITU-T G.989.2")
      subject.remove_date!
      expect(subject.content).to eq "ITU-T G.989.2"
    end

    it "does not remove version markers" do
      subject = docid("ITU-T H.264 (V14) (08/2021)")
      subject.remove_date!
      expect(subject.content).to eq "ITU-T H.264 (V14)"
    end

    it "renders the pubid canonical spelling" do
      subject = docid("ITU-T H.222.0 v10 (04/2025)")
      subject.remove_date!
      expect(subject.content).to eq "ITU-T H.222.0 (V10)"
    end

    context "when the content does not parse" do
      it "leaves the content unchanged" do
        subject = docid("ITU-R RR (2020)")
        subject.remove_date!
        expect(subject.content).to eq "ITU-R RR (2020)"
      end

      it "leaves a reference without a publisher unchanged" do
        subject = docid("H.264 (2005) Amd. 1 (06/2006)")
        subject.remove_date!
        expect(subject.content).to eq "H.264 (2005) Amd. 1 (06/2006)"
      end

      it "leaves an ISO co-identifier unchanged" do
        subject = docid("ISO/IEC 14496-10", type: "ISO")
        subject.remove_date!
        expect(subject.content).to eq "ISO/IEC 14496-10"
      end
    end
  end
end
