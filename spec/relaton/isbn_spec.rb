RSpec.describe Relaton::Isbn do
  it "has a version number" do
    expect(Relaton::Isbn::VERSION).not_to be nil
  end

  it "returns grammar hash" do
    gh = Relaton::Isbn.grammar_hash
    expect(gh).to be_instance_of String
    expect(gh.length).to eq 32
  end

  context "get" do
    it "success", vcr: "success" do
      bib = Relaton::Isbn::OpenLibrary.get "ISBN 9780120644810"
      expect(bib).to be_instance_of Relaton::Bib::ItemData
      expect(bib.docidentifier.first.content).to eq "9780120644810"
    end
  end
end
