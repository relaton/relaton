# frozen_string_literal: true

# Pure pubid round-trip checks (no HTTP). These guard the two things the JCGM
# migration hinges on: (1) that every stored id is a Pubid::Jcgm identifier that
# round-trips through from_hash/to_hash, so Relaton::Index accepts the index, and
# (2) the naive last-digit ordinal (11st/12nd/13rd — NO teens exception), which
# the real records print and which pubid must reproduce.
RSpec.describe "Pubid::Jcgm round-trip" do
  def round_trips(id_str)
    id = ::Pubid::Jcgm.parse(id_str)
    hash = id.to_hash
    back = ::Pubid::Jcgm::Identifier.from_hash(hash)
    expect(back.to_s).to eq(id.to_s)
    expect(back.to_hash).to eq(hash)
    hash
  end

  context "meetings (naive last-digit ordinal, no teens exception)" do
    {
      "JCGM 11st Meeting (2006)" => "11",
      "JCGM 12nd Meeting (2007)" => "12",
      "JCGM 13rd Meeting (2008)" => "13",
      "JCGM 17th Meeting (2012)" => "17",
      "JCGM 21st Meeting (2017)" => "21",
      "JCGM 22nd Meeting (2018)" => "22",
      "JCGM 23rd Meeting (2020)" => "23",
    }.each do |id_str, number|
      it "round-trips #{id_str.inspect}" do
        hash = round_trips(id_str)
        expect(hash["_type"]).to eq("pubid:jcgm:meeting")
        expect(hash["number"]).to eq(number)
      end
    end

    it "prints 11st / 12nd / 13rd (not 11th/12th/13th)" do
      expect(::Pubid::Jcgm.parse("JCGM 11st Meeting (2006)").to_s).to eq("JCGM 11st Meeting (2006)")
      expect(::Pubid::Jcgm.parse("JCGM 12nd Meeting (2007)").to_s).to eq("JCGM 12nd Meeting (2007)")
      expect(::Pubid::Jcgm.parse("JCGM 13rd Meeting (2008)").to_s).to eq("JCGM 13rd Meeting (2008)")
    end
  end

  context "guides and GUM guides" do
    it "round-trips a guide with _type pubid:jcgm:guide" do
      expect(round_trips("JCGM 200:2012")["_type"]).to eq("pubid:jcgm:guide")
      expect(round_trips("JCGM 100:2008")["_type"]).to eq("pubid:jcgm:guide")
    end

    it "round-trips a GUM guide with _type pubid:jcgm:gum-guide" do
      expect(round_trips("JCGM GUM-6:2020")["_type"]).to eq("pubid:jcgm:gum-guide")
    end
  end

  # The three legacy static forms that older pubid couldn't parse are now
  # supported on pubid main: the bare `GUM`/`VIM-N` guides and the `Corrigendum`
  # suffix (which introduces a distinct `corrigendum` type).
  context "legacy static forms (now supported)" do
    it "round-trips the bare GUM/VIM-N guides as guides" do
      expect(round_trips("JCGM GUM")["_type"]).to eq("pubid:jcgm:guide")
      expect(round_trips("JCGM VIM-3")["_type"]).to eq("pubid:jcgm:guide")
    end

    it "round-trips a corrigendum, carrying its base guide" do
      hash = round_trips("JCGM 200:2008 Corrigendum")
      expect(hash["_type"]).to eq("pubid:jcgm:corrigendum")
      expect(hash.dig("base", "_type")).to eq("pubid:jcgm:guide")
      expect(hash.dig("base", "number")).to eq("200")
    end
  end
end
