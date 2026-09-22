require "relaton/gb/gb_scraper"

RSpec.describe Relaton::Gb::Scraper do
  it "returns status published" do
    doc = Nokogiri::HTML <<~END_HTML
      <html>
        <body>
          <table>
            <tr>
              <td>标准状态<span>即将实施</span></td>
            </tr>
          </table>
        </body>
      </html>
    END_HTML
    status = Relaton::Gb::GbScraper.get_status doc
    expect(status.stage.content).to eq "published"
  end

  it "returns guidelines" do
    expect(Relaton::Gb::GbScraper.send(:get_mandate, "GB/Z 1234-2020")).to eq "guidelines"
  end

  it "returns recommended" do
    expect(Relaton::Gb::GbScraper.send(:get_mandate, "JB/T 13368-2018")).to eq "recommended"
  end

  it "returns mandatory" do
    expect(Relaton::Gb::GbScraper.send(:get_mandate, "GB 19855-2005")).to eq "mandatory"
  end

  it "returns mandatory for a social group standard" do
    expect(Relaton::Gb::GbScraper.send(:get_mandate, "T/GZAEPI 001-2018")).to eq "mandatory"
  end

  describe "#get_prefix" do
    it "reads the publisher code of a national standard" do
      expect(Relaton::Gb::GbScraper.send(:get_prefix, "GB/T 20223-2006")["prefix"]).to eq "GB_national"
    end

    it "reads the publisher code of a sector standard" do
      expect(Relaton::Gb::GbScraper.send(:get_prefix, "JB/T 13368-2018")["prefix"]).to eq "JB_mechanical"
    end
  end

  describe "#get_gbtype" do
    it "reads the prefix of a confidential standard" do
      gbtype = Relaton::Gb::GbScraper.send(:get_gbtype, Nokogiri::HTML("<html/>"), "GBn 123-1990")
      expect(gbtype.prefix).to eq "GBn_confidential"
    end

    # `ZB` has no prefixes.yaml entry, and `DB11/T` does not parse with
    # Pubid::Gb. Neither may raise: a portal docref is data.
    ["ZB 123-2020", "DB11/T 123-2020"].each do |ref|
      it "leaves the prefix nil for #{ref}" do
        gbtype = Relaton::Gb::GbScraper.send(:get_gbtype, Nokogiri::HTML("<html/>"), ref)
        expect(gbtype.prefix).to be_nil
      end
    end
  end

  describe "#parse_docref" do
    it "returns the undated, part-less id, the part and the year" do
      expect(Relaton::Gb::GbScraper.send(:parse_docref, "GB/T 5606.1-2004")).to eq ["GB/T 5606", "1", "2004"]
    end

    it "returns nil for a missing part" do
      expect(Relaton::Gb::GbScraper.send(:parse_docref, "JB/T 13368-2018")).to eq ["JB/T 13368", nil, "2018"]
    end

    it "returns the social group id without the year" do
      expect(Relaton::Gb::GbScraper.send(:parse_docref, "T/GZAEPI 001-2018")).to eq ["T/GZAEPI 001", nil, "2018"]
    end
  end

  it "returns scope sector" do
    doc = Nokogiri::HTML <<~END_HTML
      <html>
        <body>
          <div>发布单位</div>
          <div>行业标准</div>
        </body>
      </html>
    END_HTML

    expect(Relaton::Gb::GbScraper.send(:get_scope, doc)).to eq "sector"
  end
end
