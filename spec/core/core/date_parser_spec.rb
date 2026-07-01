describe Relaton::Core::DateParser do
  include Relaton::Core::DateParser

  describe "#parse_date" do
    it "parses 'February 2012'" do
      expect(parse_date("February 2012")).to eq "2012-02"
    end

    it "parses 'February 11, 2012'" do
      expect(parse_date("February 11, 2012")).to eq "2012-02-11"
    end

    it "parses '2012-02-03'" do
      expect(parse_date("2012-02-03")).to eq "2012-02-03"
    end

    it "parses '2012-2-3'" do
      expect(parse_date("2012-2-3")).to eq "2012-02-03"
    end

    it "parses '2012-02'" do
      expect(parse_date("2012-02")).to eq "2012-02"
    end

    it "parses '2012-2'" do
      expect(parse_date("2012-2")).to eq "2012-02"
    end

    it "parses '2012'" do
      expect(parse_date("2012")).to eq "2012"
    end
  end
end
