RSpec.describe Relaton::Ieee::Bibliography do
  it "raise RequestError is domain not reacheable" do
    expect(Relaton::Index).to receive(:find_or_create).and_raise Faraday::ConnectionFailed.new("Connection error")
    expect { described_class.search "ref" }.to raise_error Relaton::RequestError
  end

  # relaton#205: Relaton::Db passes the pubid it parsed. It is used as it is,
  # not parsed a second time.
  it "takes a parsed pubid without a second parse" do
    pubid = Pubid::Ieee::Identifier.parse "IEEE 528-2019"
    expect(described_class.send(:parse_pubid, pubid)).to be pubid
  end
end

RSpec.describe Relaton::Ieee::Bibliography, "row selection" do
  # The preloaded fixture index (spec/ieee/support/webmock.rb) holds every
  # 528 and 754 row of the published index: editions, redlines and drafts.
  def row(ref, year = nil)
    described_class.send(:find_row, Pubid::Ieee::Identifier.parse(ref), year)&.dig(:file)
  end

  it "takes the latest edition of an undated reference" do
    expect(row("IEEE 528")).to eq "data/ieee-std-528-2019.yaml"
    expect(row("IEEE 754")).to eq "data/ieee-std-754-2019.yaml"
  end

  it "takes the stated year" do
    expect(row("IEEE 528-2001")).to eq "data/ieee-std-528-2001.yaml"
    expect(row("IEEE 528", "1994")).to eq "data/ieee-std-528-1994.yaml"
  end

  it "takes a redline only when the reference names it" do
    expect(row("IEEE Std 754-2019 - Redline")).to eq "data/ieee-std-754-2019-redline.yaml"
  end

  it "takes the publisher the reference names" do
    expect(row("ANSI/IEEE 528")).to eq "data/ansi-ieee-528-1984.yaml"
  end
end

RSpec.describe Relaton::Ieee::Bibliography, "project-draft reference" do
  # relaton-ieee#25: "IEEE P802.21/D14" parses as a ProjectDraft, but the
  # pre-publication crawl record is a Standard with draft_status "Unapproved"
  # ("IEEE Unapproved 802.21/D14, Sept 2008") — the equality match cannot
  # cross the classes and the row string never carries the P, so the
  # substring fallback also has to try the stripped form.
  it "reaches the Unapproved record through its project spelling" do
    VCR.use_cassette "ieee_p802_21_d14" do
      item = Relaton::Ieee::Bibliography.search("IEEE P802.21/D14")
      expect(item.docidentifier.first.content).to eq "IEEE Unapproved Draft P802.21/D14, Sep 2008"
    end
  end

  it "does not answer a project reference without its draft number" do
    expect(Relaton::Ieee::Bibliography.search("IEEE P802.21")).to be_nil
  end
end
