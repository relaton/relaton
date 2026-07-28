# frozen_string_literal: true

RSpec.describe Relaton::Jcgm do
  it "has an index file name" do
    expect(described_class::INDEXFILE).to eq "index-v1"
  end

  it "derives grammar_hash from the relaton version" do
    expect(described_class.grammar_hash).to eq Digest::MD5.hexdigest(Relaton::VERSION)
  end

  describe "index round-trip (pubid _type serialization)" do
    it "emits and reloads every fixture row through pubid_class without rejection" do
      require "zip"
      require "tmpdir"
      zip_path = File.expand_path("../fixtures/#{described_class::INDEXFILE}.zip", __dir__)
      yaml = Zip::File.open(zip_path) { |z| z.first.get_input_stream.read }
      Dir.mktmpdir("jcgm-index") do |dir|
        file = File.join(dir, "#{described_class::INDEXFILE}.yaml")
        File.write file, yaml
        rows = Relaton::Index::Type.new(:jcgm, nil, file, nil, ::Pubid::Jcgm::Identifier).index
        # Every row's id came back as a concrete Pubid::Jcgm identifier subtype.
        expect(rows).not_to be_empty
        expect(rows.map { |r| r[:id] }).to all(be_a(::Pubid::Jcgm::Identifier))
        types = rows.map { |r| r[:id].to_hash["_type"] }.uniq.sort
        expect(types).to eq ["pubid:jcgm:corrigendum", "pubid:jcgm:guide",
                             "pubid:jcgm:gum-guide", "pubid:jcgm:meeting"]
      end
    end
  end
end
