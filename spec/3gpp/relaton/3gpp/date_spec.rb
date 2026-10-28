describe Relaton::ThreeGpp::Date do
  it "accepts the release date types" do
    %w[published project-start released].each do |type|
      expect { described_class.new(type: type, at: "1999-12-17").validate! }.not_to raise_error
    end
  end

  it "rejects an unknown type" do
    date = described_class.new(type: "project-end", at: "1999-12-17")
    expect { date.validate! }.to raise_error(Lutaml::Model::ValidationError)
  end
end
