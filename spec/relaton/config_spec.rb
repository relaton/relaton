describe Relaton do
  after { described_class.instance_variable_set :@configuration, nil }

  it "configure" do
    described_class.configure do |conf|
      conf.use_api = true
    end
    expect(described_class.configuration.use_api).to be true
  end
end
