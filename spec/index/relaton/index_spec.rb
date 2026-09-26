# frozen_string_literal: true

RSpec.describe Relaton::Index do
  let(:file) { File.join(Dir.home, ".relaton", "iso", "index.yaml") }

  before do
    described_class.instance_variable_set(:@pool, nil)
  end

  it "has a version number" do
    expect(Relaton::VERSION).not_to be nil
  end

  context "#find_or_create" do
    subject { described_class.find_or_create("ISO", url: :url, file: :file) }
    it { is_expected.to be_a(Relaton::Index::Type) }
  end

  context "#find_or_create with deprecated id_keys" do
    it "warns and ignores the key" do
      expect(Relaton.logger_pool).to receive(:warn)
        .with(/id_keys is deprecated/, "relaton-index").and_call_original
      expect(described_class.find_or_create("ISO", file: :deprecated_file, id_keys: :keys))
        .to be_a(Relaton::Index::Type)
    end
  end

  it "remove local index" do
    idx = described_class.find_or_create("ISO", url: true)
    expect(described_class.config.storage).to receive(:remove).with(file)
    idx.remove_file
  end

  it "close" do
    pool = Relaton::Index::Pool.new
    expect(pool).to receive(:remove).with(:IHO)
    described_class.instance_variable_set(:@pool, pool)
    described_class.close :IHO
  end

  context "config" do
    it "default" do
      expect(Relaton::Index.config).to be_a Relaton::Index::Config
      expect(Relaton::Index.config.storage).to eq Relaton::Index::FileStorage
      expect(Relaton::Index.config.storage_dir).to eq Dir.home
    end

    it "configure storage" do
      Relaton::Index.configure do |config|
        config.storage = :custom_storage
      end
      expect(Relaton::Index.config.storage).to eq :custom_storage
    end

    it "configure storage_dir" do
      Relaton::Index.configure do |config|
        config.storage_dir = "/"
      end
      expect(Relaton::Index.config.storage_dir).to eq "/"
    end

    it "configure filename" do
      Relaton::Index.configure do |config|
        config.filename = "index-new.yml"
      end
      expect(Relaton::Index.config.filename).to eq "index-new.yml"
    end
  end
end
