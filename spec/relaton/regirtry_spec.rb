RSpec.describe Relaton::Registry do
  it "outputs backend not present" do
    stub_const "Relaton::Registry::SUPPORTED_GEMS", ["not_supported_gem"]
    expect { Relaton::Registry.clone.instance }.to output(
      /backend not_supported_gem not present/,
    ).to_stdout
  end

  it "finds processor" do
    expect(Relaton::Registry.instance.find_processor("relaton_iso")).
      to be_instance_of RelatonIso::Processor
  end

  it "returns supported processors" do
    expect(Relaton::Registry.instance.supported_processors).to include :relaton_iso
  end

  it "finds processor by type" do
    expect(Relaton::Registry.instance.by_type("ISO")).to be_instance_of RelatonIso::Processor
  end
end
