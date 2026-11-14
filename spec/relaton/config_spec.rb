describe Relaton::Db do
  after { described_class.instance_variable_set :@configuration, nil }

  it "configure" do
    described_class.configure do |conf|
      conf.use_api = true
    end
    expect(described_class.configuration.use_api).to be true
  end

  # The API tier (relaton#535) is opt-in; a program that cannot run Ruby
  # configuration, such as the CLI, turns it on from the environment.
  context "environment" do
    around do |ex|
      old = ENV.to_h.slice("RELATON_USE_API", "RELATON_API_HOST")
      described_class.instance_variable_set :@configuration, nil
      ex.run
    ensure
      %w[RELATON_USE_API RELATON_API_HOST].each { ENV.delete _1 }
      ENV.update old
    end

    def config = described_class.configuration

    it "turns the API tier on with RELATON_USE_API" do
      %w[1 true YES on].each do |value|
        ENV["RELATON_USE_API"] = value
        described_class.instance_variable_set :@configuration, nil
        expect(config.use_api).to be(true), value
      end
    end

    it "leaves the API tier off without RELATON_USE_API" do
      ENV.delete "RELATON_USE_API"
      expect(config.use_api).to be false
    end

    it "leaves the API tier off with RELATON_USE_API=0" do
      ENV["RELATON_USE_API"] = "0"
      expect(config.use_api).to be false
    end

    it "reads the API host from RELATON_API_HOST" do
      ENV["RELATON_API_HOST"] = " https://api.example.org/ "
      expect(config.api_host).to eq "https://api.example.org/"
    end

    it "ignores a RELATON_API_HOST that is not an http(s) URL" do
      %w[api.example.org ftp://api.example.org http://].each do |value|
        ENV["RELATON_API_HOST"] = value
        described_class.instance_variable_set :@configuration, nil
        expect { expect(config.api_host).to eq "https://api.relaton.org" }
          .to output(/RELATON_API_HOST/).to_stderr_from_any_process
      end
    end

    it "uses api.relaton.org without RELATON_API_HOST" do
      ENV.delete "RELATON_API_HOST"
      expect(config.api_host).to eq "https://api.relaton.org"
      ENV["RELATON_API_HOST"] = ""
      described_class.instance_variable_set :@configuration, nil
      expect(config.api_host).to eq "https://api.relaton.org"
    end
  end
end
