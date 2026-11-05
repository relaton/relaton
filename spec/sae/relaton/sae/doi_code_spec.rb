describe Relaton::Sae::DoiCode do
  def code(doi, approved = nil)
    described_class.parse(doi, approved_year: approved)
  end

  context "a J-series edition, dated by its DOI" do
    subject(:sae) { code "10.4271/j3016_202104" }

    it { expect(sae.native).to eq "SAE J3016_202104" }
    it { expect(sae.year).to eq "2021" }
    it { expect(sae.reference).to eq "SAE J3016_202104" }

    it "takes the year from the DOI, not from the approval date" do
      expect(code("10.4271/j3016_202104", "2020").year).to eq "2021"
    end
  end

  context "an aerospace revision, with no date in its DOI" do
    subject(:sae) { code "10.4271/ams4121j", "2017" }

    it { expect(sae.native).to eq "SAE AMS4121J" }
    it { expect(sae.reference).to eq "SAE AMS4121J:2017" }

    it "has no year when the record has no approval date" do
      expect(code("10.4271/ams4121j").reference).to eq "SAE AMS4121J"
    end
  end

  it "keeps a part" do
    expect(code("10.4271/j2337/2_201702").native).to eq "SAE J2337/2_201702"
  end

  it "keeps an underscore that is not an edition date in the code" do
    expect(code("10.4271/as5259/7a_a1").native).to eq "SAE AS5259/7A_A1"
    expect(code("10.4271/j1939da_4q2012")).to have_attributes(
      native: "SAE J1939DA_4Q2012", date: nil,
    )
  end

  it "reads the DOI case-insensitively" do
    expect(code("10.4271/J3016_202104").native).to eq "SAE J3016_202104"
  end

  it "rejects a DOI outside the SAE prefix" do
    expect(code("10.1000/j3016_202104")).to be_nil
  end

  it "rejects a DOI that names no code" do
    expect(code("10.4271/")).to be_nil
    expect(code(nil)).to be_nil
  end

  describe "#printed" do
    it "spells the code the way SAE prints it" do
      expect(code("10.4271/amsqqa250/4b").printed).to eq "SAE AMS-QQ-A-250/4B"
      expect(code("10.4271/j3016_202104").printed).to eq "SAE J3016_202104"
    end

    it "keeps the DOI's spelling of a code pubid cannot read" do
      expect(code("10.4271/cpgm2016").printed).to eq "SAE CPGM2016"
    end
  end
end
