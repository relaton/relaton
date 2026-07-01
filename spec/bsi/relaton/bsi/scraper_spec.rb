describe Relaton::Bsi::Scraper do
  context "#owner_entity" do
    let(:hit) { Relaton::Bsi::Hit.new(publisher: "Org Name") }

    it "returns organization" do
      org = Relaton::Bsi::Scraper.send :owner_entity, hit
      expect(org).to be_instance_of Relaton::Bib::Organization
      expect(org.name[0].content).to eq "Org Name"
    end
  end
end
