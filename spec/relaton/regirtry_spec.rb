RSpec.describe Relaton::Registry do
  it "outputs backend not present" do
    stub_const "Relaton::Registry::SUPPORTED_GEMS", ["not_supported_gem"]
    expect { Relaton::Registry.clone.instance }.to output(
      /backend not_supported_gem not present/
    ).to_stdout
  end

  it "finds ISO processor" do
    expect(Relaton::Registry.instance.find_processor("relaton_iso"))
      .to be_instance_of RelatonIso::Processor
  end

  it "returns supported processors" do
    expect(Relaton::Registry.instance.supported_processors).to include :relaton_iso
  end

  it "finds processor by type" do
    expect(Relaton::Registry.instance.by_type("CN")).to be_instance_of RelatonGb::Processor
  end

  it "finds processor by type" do
    expect(Relaton::Registry.instance.by_type("IEC")).to be_instance_of RelatonIec::Processor
  end

  it "finds processor by type" do
    expect(Relaton::Registry.instance.by_type("IETF")).to be_instance_of RelatonIetf::Processor
  end

  it "finds processor by type" do
    expect(Relaton::Registry.instance.by_type("ISO")).to be_instance_of RelatonIso::Processor
  end

  it "finds processor by type" do
    expect(Relaton::Registry.instance.by_type("ITU")).to be_instance_of RelatonItu::Processor
  end

  it "finds processor by type" do
    expect(Relaton::Registry.instance.by_type("NIST")).to be_instance_of RelatonNist::Processor
  end

  it "finds processor by type" do
    expect(Relaton::Registry.instance.by_type("OGC")).to be_instance_of RelatonOgc::Processor
  end

  it "finds processor by type" do
    expect(Relaton::Registry.instance.by_type("CC")).to be_instance_of RelatonCalconnect::Processor
  end

  it "finds processor by type" do
    expect(Relaton::Registry.instance.by_type("OMG")).to be_instance_of RelatonOmg::Processor
  end

  it "finds processor by type" do
    expect(Relaton::Registry.instance.by_type("UN")).to be_instance_of RelatonUn::Processor
  end

  it "finds processor by type" do
    expect(Relaton::Registry.instance.by_type("W3C")).to be_instance_of RelatonW3c::Processor
  end

  it "finds processor by type" do
    expect(Relaton::Registry.instance.by_type("IEEE")).to be_instance_of RelatonIeee::Processor
  end

  it "finds processor by type" do
    expect(Relaton::Registry.instance.by_type("IHO")).to be_instance_of RelatonIho::Processor
  end

  it "finds processor by type" do
    expect(Relaton::Registry.instance.by_type("BIPM")).to be_instance_of RelatonBipm::Processor
  end

  it "finds processor by type" do
    expect(Relaton::Registry.instance.by_type("ECMA")).to be_instance_of RelatonEcma::Processor
  end
end
