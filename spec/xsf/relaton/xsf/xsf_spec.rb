describe Relaton::Xsf do
  it ".grammar_hash" do
    expect(described_class.grammar_hash).to eq Digest::MD5.hexdigest(Relaton::VERSION)
  end
end
