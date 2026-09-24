describe Relaton::Index::Pool do
  it "create Pool" do
    expect(subject.instance_variable_get(:@pool)).to eq({})
  end

  context "instace methods" do
    context "#type" do
      context "when getting specific type first time" do
        subject { described_class.new.type("ISO", url: :url, file: :file, id_keys: :keys) }

        it { expect(subject).to be_a(Relaton::Index::Type) }
      end

      context "when getting already created specific type" do
        it "returns existing Type" do
          # create type first time
          type = subject.type("ISO", url: :url, file: :file, id_keys: :keys)
          expect(subject.type(:ISO, url: :url, file: :file)).to eq(type)
        end
      end

      context "when same type, but different arguments" do
        it "creates new Type" do
          # create type first time
          type = subject.type("ISO", url: :url, file: :file, id_keys: :keys)
          expect(subject.type(:ISO, url: :url2, file: :file2)).not_to eq(type)
        end
      end

      context "when only pages_url changes" do
        it "creates new Type" do
          type = subject.type("ISO", pages_url: "https://a.io/", pubid_class: TestIdentifier)
          expect(subject.type("ISO", pages_url: "https://a.io/")).to eq(type)
          expect(subject.type("ISO", pages_url: "https://b.io/")).not_to eq(type)
        end
      end
    end

    it "#remove" do
      subject.instance_variable_set(:@pool, { ISO: :idx })
      subject.remove :ISO
      expect(subject.instance_variable_get(:@pool)).to eq({})
    end
  end
end
