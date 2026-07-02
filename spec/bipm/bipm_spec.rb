RSpec.describe Relaton::Bipm do
  it "has a version number" do
    expect(Relaton::Bipm::VERSION).not_to be nil
  end

  it "retur grammar hash" do
    hash = Relaton::Bipm.grammar_hash
    expect(hash).to be_instance_of String
    expect(hash.size).to eq 32
  end
end
