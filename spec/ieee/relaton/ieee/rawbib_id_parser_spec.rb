require "relaton/ieee/data_fetcher"

RSpec.describe Relaton::Ieee::RawbibIdParser do
  # it do
  #   ids = {}
  #   File.readlines("fixtures/normtitles.txt", encoding: "UTF-8").each do |nt|
  #     id = RelatonIeee::RawbibIdParser.parse(nt.strip)
  #     # expect(id).not_to be_nil
  #     # expect(ids[id]).to be_nil
  #     ids[id] ||= nt.strip if id
  #   end
  #   ids
  # end

  # it do
  #   pid = RelatonIeee::RawbibIdParser.parse "IEEE Std 802.15.4j-2013 (Amendment to IEEE Std 802.15.4-2011 as amended by IEEE Std 802.15.4e-2012, IEEE Std 802.15.4f-2012, and IEEE Std 802.15.4g-2012)"
  #   id = pid.to_s
  #   id
  # end

  context "converts 2 digit year to 4 digit year" do
    it "4 digit year" do
      y = (Date.today.year + 1).to_s
      expect(described_class.yn(y)).to eq y
    end

    it "this century" do
      y = Date.today.year.to_s
      expect(described_class.yn(y[2..3])).to eq y
    end

    it "previous century" do
      y = Date.today.year.to_s[2..4].to_i + 1
      expect(described_class.yn(y.to_s)).to eq "19#{y}"
    end
  end

  context "coverts edition name to number" do
    it "First" do
      expect(described_class.en("First")).to eq 1
    end

    it "Second" do
      expect(described_class.en("Second")).to eq 2
    end

    it "3rd" do
      expect(described_class.en("3")).to eq "3"
    end
  end

  it "parse sdtnumber" do
    pubid = described_class.parse("", "802.15.4j-2013")
    expect(pubid.to_s).to eq "IEEE Std 802.15.4j-2013"
  end

  # The bespoke Renderer is only *returned* when a pubid parse loses a digit, so
  # `parse` alone can't pin its rendering while pubid handles this id. Assert it
  # directly: the fallback must spell the amendment in pubid's canonical spaced
  # form, so an id that does miss the faithfulness guard still renders `/Amd N`.
  it "renders the amendment in the canonical spaced form in the fallback" do
    nt = "IS0/IEC/IEEE 8802-11:2012/Amd.5:2015(E) (Adoption of IEEE Std 802.11af-2014)"
    rendered = described_class.parse_fallback(nt, "")
    expect(rendered.to_s).to eq "ISO/IEC/IEEE 802.11/Amd 5-2012"
    # `to_id` is fed back to pubid, so the spaced form must stay parseable.
    expect(described_class.pubid_parse(rendered.to_id)).not_to be_nil
  end

  # `IdamsParser` renders the `scope: trademark` docidentifier with
  # `to_s(trademark: true)` on whatever `parse` returned, so the fallback's ®/™
  # rule has to agree with pubid's (metanorma/pubid#322): the mark attaches to
  # the document number, and the 802/8802/2030 registered series keep ® even
  # behind a project `P`.
  context "trademark rendering in the fallback" do
    def render(nt)
      described_class.parse_fallback(nt, "").to_s(trademark: true)
    end

    it "attaches the mark to the number, ahead of the draft and year" do
      expect(render("IEEE Std P1073.2.0/D0.05")).to eq "IEEE Std P1073.2.0™/D-0.05"
    end

    it "keeps ® on a registered series behind a project P" do
      expect(render("IEEE Std P802.8/D3.2")).to eq "IEEE Std P802.8®/D-3.2"
    end

    it "keeps ™ off the registered series" do
      expect(render("IEEE Std P1073.1.3.11/D3.0")).to eq "IEEE Std P1073.1.3.11™/D-3.0"
    end
  end

  shared_examples "parse normtitle" do |nt, id|
    it "parse #{nt}" do
      expect(described_class.parse(nt, "").to_s).to eq id
    end
  end

  it_behaves_like "parse normtitle", "A.I.E.E. No. 15 May-1928", "AIEE No 15-192805"
  it_behaves_like "parse normtitle", "IEEE Std P1073.1.3.4/D3.0", "IEEE Std P11073.00101"
  it_behaves_like "parse normtitle", "IEEE P1073.2.1.1/D08", "IEEE P1073.2.1.1/D08"
  it_behaves_like "parse normtitle", "IEEE P802.1Qbu/03.0, July 2015", "IEEE P802.1Qbu/D3.0"
  it_behaves_like "parse normtitle", "IEEE P11073-10422/04, November 2015", "IEEE P11073-10422/D04, November 2015"
  it_behaves_like "parse normtitle", "IEEE P802.11aqTM/013.0 October 2017", "IEEE P802.11aqTM/D13.0"
  it_behaves_like "parse normtitle", "IEEE P844.3/C22.2 293.3/D0, August 2018", "IEEE P844.3-2018"
  it_behaves_like "parse normtitle", "IEEE P844.3/C22.2 293.3/D1, November 2018", "IEEE P844.3/D1"
  it_behaves_like "parse normtitle", "AIEE No 431 (105) -1958", "AIEE No 431 (105)-1958"
  it_behaves_like "parse normtitle", "IEEE 1076-CONC-I99O", "IEEE 1076-199O"
  it_behaves_like "parse normtitle", "IEEE Std 960-1993, IEEE Std 1177-1993", "IEEE Std 960-1993 and IEEE Std 1177-1993"
  it_behaves_like "parse normtitle", "IEEE P802.11ajD8.0, August 2017", "IEEE P802.11aj/D8.0, August, 2017"
  it_behaves_like "parse normtitle", "IEEE P802.11ajD9.0, November 2017", "IEEE P802.11aj/D9.0, November, 2017"
  it_behaves_like "parse normtitle", "ISO/IEC/IEEE P29119-4-DISMay2013", "ISO/IEC/IEEE 29119.4.DISMay2013"
  it_behaves_like "parse normtitle", "IEEE-P15026-3-DIS-January 2015", "ISO/IEC/IEEE P15026-3/DDIS January, 2015"
  it_behaves_like "parse normtitle", "ANSI/IEEE PC63.7/D rev17, December 2014", "ANSI/IEEE C63.7-2014Rev17"
  it_behaves_like "parse normtitle", "IEC/IEEE P62271-37-013:2015 D13.4", "IEC/IEEE 62271.37.013/D13.4"
  it_behaves_like "parse normtitle", "PC37.30.2/D043 Rev 18, May 2015", "IEEE Std PC37.30.2Rev18/D043"
  it_behaves_like "parse normtitle", "IEC/IEEE FDIS 62582-5 IEC/IEEE 2015", "IEC/IEEE FDIS 62582.5:2015"
  it_behaves_like "parse normtitle", "ISO/IEC/IEEE P15289:2016, 3rd Ed FDIS/D2", "ISO/IEC/IEEE FDIS P15289./E-3/D-2-2016"
  it_behaves_like "parse normtitle", "IEEE P802.15.4REVi/D09, April 2011 (Revision of IEEE Std 802.15.4-2006)", "IEEE P802.15.4/D09, April, 2011"
  it_behaves_like "parse normtitle", "Draft IEEE P802.15.4REVi/D09, April 2011 (Revision of IEEE Std 802.15.4-2006)", "IEEE P802.15.4Revi/D09, 04 2011"
  it_behaves_like "parse normtitle", "ISO/IEC/IEEE DIS P42020:201x(E), June 2017", "ISO/IEC/IEEE DIS 42020:2017"
  it_behaves_like "parse normtitle", "IEEE/IEC P62582 CD2 proposal, May 2017", "IEEE/IEC CD2 P62582-2017-05"
  it_behaves_like "parse normtitle", "ISO/IEC/IEEE P16326:201x WD.4a, July 2017", "ISO/IEC/IEEE 16326-2017-07/D4a"
  it_behaves_like "parse normtitle", "ISO/IEC/IEEE CD.1 P21839, October 2017", "ISO/IEC/IEEE CD1 P21839-2017-10"
  it_behaves_like "parse normtitle", "IEEE P3001.2/D5, August 2017", "IEEE P3001.2/D5, August, 2017"
  it_behaves_like "parse normtitle", "P3001.2/D5, August 2017", "IEEE P3001.2/D5, August, 2017"
  it_behaves_like "parse normtitle", "ISO/IEC/IEEE P16326:201x WD5, December 2017", "ISO/IEC/IEEE 16326-2017-12/D5"
  it_behaves_like "parse normtitle", "ISO/IEC/IEEE DIS P16326/201x, December 2018", "ISO/IEC/IEEE DIS 16326:2018"
  it_behaves_like "parse normtitle", "ISO/IEC/IEEE/P21839, 2019(E)", "ISO/IEC/IEEE P21839.2019/P"
  it_behaves_like "parse normtitle", "ISO/IEC/IEEE P42020/V1.9, August 2018", "ISO/IEC/IEEE 42020/DV1.9, August, 2018"
  it_behaves_like "parse normtitle", "ISO/IEC/IEEE CD2 P12207-2: 201x(E), February 2019", "ISO/IEC/IEEE CD2 P12207.2-2019-02"
  it_behaves_like "parse normtitle", "ISO/IEC/IEEE P42010.WD4:2019(E)", "ISO/IEC/IEEE P42010.2019/D4"
  it_behaves_like "parse normtitle", "IEC/IEEE P63195_CDV/V3, February 2020", "IEC/IEEE CDV 63195:2020"
  it_behaves_like "parse normtitle", "ISO /IEC/IEEE P24774_D1, February 2020", "ISO/IEC/IEEE 24774/D1, February, 2020"
  it_behaves_like "parse normtitle", "IEEE/ISO/IEC P42010.CD1-V1.0, April 2020", "IEEE/ISO/IEC CD1 P42010-2020-04"
  it_behaves_like "parse normtitle", "ISO/IEC/IEEE/P16085_DIS, March 2020", "ISO/IEC/IEEE DIS 16085:2020"
  it_behaves_like "parse normtitle", "ISO/IEC/IEEE P24774/DIS, July 2020", "ISO/IEC/IEEE 24774/DDIS, July 2020"
  it_behaves_like "parse normtitle", "ANSI/IEEE Std: Outdoor Apparatus Bushings", "ANSI/IEEE 21-1976-11"
  it_behaves_like "parse normtitle", "Unapproved Draft Std ISO/IEC FDIS 15288:2007(E) IEEE P15288/D3,", "ISO/IEC/IEEE FDIS 15288:2007"
  it_behaves_like "parse normtitle", "Draft National Electrical Safety Code, January 2016", "IEEE Std PC2-2016-01"
  it_behaves_like "parse normtitle", "ANSI/IEEE-ANS-7-4.3.2-1982", "ANSI/IEEE/ANS 7.4-3-2-1982"
  it_behaves_like "parse normtitle", "IEEE Unapproved Draft Std P802.1AB/REVD2.2, Dec 2007", "IEEE Unapproved Draft P802.1AB/D2.2, Dec 2007"
  it_behaves_like "parse normtitle", "International Standard ISO/IEC 8802-9: 1996(E) ANSI/IEEE Std 802.9, 1996 Edition", "ISO/IEC/IEEE 802.9-1996"
  it_behaves_like "parse normtitle", "ISO/IEC13210: 1994 (E) ANSI/IEEE Std 1003.3-1991", "ISO/IEC/IEEE 13210-1994"
  it_behaves_like "parse normtitle", "J-STD-016-1995", "IEEE Std 016-1995"
  it_behaves_like "parse normtitle", "Std 802.1ak-2007 (Amendment to IEEE Std 802.1QTM-2005)", "IEEE Std 802.1ak-2007"
  it_behaves_like "parse normtitle", "IS0/IEC/IEEE 8802-11:2012/Amd.5:2015(E) (Adoption of IEEE Std 802.11af-2014)", "ISO/IEC/IEEE 802.11/Amd 5-2012"
  it_behaves_like "parse normtitle", "National Electrical Safety Code, C2-2012 - Redline", "C2-2012 National Electrical Safety Code"
  it_behaves_like "parse normtitle", "National Electrical Safety Code, C2-2012", "C2-2012 National Electrical Safety Code"
  it_behaves_like "parse normtitle", "2012 NESC Handbook, Seventh Edition", "IEEE Std 2012 NESC Handbook, Seventh Edition"
  it_behaves_like "parse normtitle", "Amendment to IEEE Std 802.11-2007 as amended by IEEE Std 802.11k-2008...", "IEEE Std 802.11u-2007"
  it_behaves_like "parse normtitle", "Std 11073-10417-2009", "IEEE Std 11073-10417-2009"
  it_behaves_like "parse normtitle", "ANSI/ IEEE C37.23-1969", "ANSI/IEEE C37.23-1969"
  it_behaves_like "parse normtitle", "ISO /IEC/IEEE P24774_D3, January 2021", "ISO/IEC/IEEE 24774/D3, January, 2021"
  it_behaves_like "parse normtitle", "Nuclear EQ Sourcebook and Supplement", "IEEE Std 7438946"
  it_behaves_like "parse normtitle", "IEEE Unapproved Draft Std P802.3-2008 (P802.3bb)/Cor 1/D2.0, Jul 2009", "IEEE Unapproved Draft P802.3/D2.0, Jul 2009 (IEEE P802.3bb)/Cor. 1"

  # Defect 1: mn() must normalize non-canonical month names (case, 4-letter
  # "Sept", OCR typos, day-suffix garble) to a numeric month, and omit a
  # genuinely unrecognizable one — an id with a name-suffixed month is rejected
  # by pubid, but a numeric or absent month parses.
  context "normalizes month names (mn)" do
    {
      "Sept" => "09", "sept" => "09", "june" => "06", "feb" => "02",
      "Feburary" => "02", "Novemer" => "11", "Octobor" => "10", "Janurary" => "01",
      "Sep20" => "09", "Feb20" => "02", "Oct20" => "10", "Dec20" => "12",
      "May" => "05", "January" => "01", "Jul" => "07", "07" => "07", "7" => "07",
    }.each do |input, expected|
      it "#{input.inspect} -> #{expected.inspect}" do
        expect(described_class.mn(input)).to eq expected
      end
    end

    it "omits a genuinely unrecognizable month" do
      expect(described_class.mn("Xyzzy")).to be_nil
    end

    it "returns nil for nil" do
      expect(described_class.mn(nil)).to be_nil
    end
  end

  # Defect 1 (end to end): a leaked month name made the rendered id unparseable.
  it_behaves_like "parse normtitle", "IEEE Unapproved Draft Std PC57.2/D12, Sept 2007", "IEEE Unapproved Draft PC57.2/D12, Sep 2007"

  # Defect 2: the "Active" status word (captured with a leading space) rendered
  # as a stray token + a double space (`IEEE  Active Std ...`); it must be dropped.
  it_behaves_like "parse normtitle", "IEEE Active Unapproved Draft Std P12207.0_D2, Jul 2007", "IEEE Active Unapproved P12207.0/D2, Jul 2007"
end
