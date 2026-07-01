describe Relaton::Logger::Config do
  it "configure" do
    Relaton::Logger.configure do |conf|
      conf.logger_pool[:default] = :logger_1
      conf.logger_pool[:logger2] = :logger_2
    end
    expect(Relaton::Logger.configuration.logger_pool.loggers).to eq default: :logger_1, logger2: :logger_2
  end

  it "logger_pool=" do
    Relaton::Logger.configuration.logger_pool = { default: :logger_1, logger2: :logger_2 }
    expect(Relaton::Logger.configuration.logger_pool.loggers).to eq default: :logger_1, logger2: :logger_2
  end
end
