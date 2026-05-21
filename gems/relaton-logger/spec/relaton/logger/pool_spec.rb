describe Relaton::Logger::Pool do
  it "initialize" do
    expect(subject.loggers).to eq({})
  end

  it "<<" do
    subject[:logger] = :logger
    expect(subject.loggers).to eq logger: :logger
  end

  it "#loggers=" do
    subject.loggers = [:logger]
    expect(subject.loggers).to eq [:logger]
  end

  it "#unknown" do
    logger = double("logger")
    expect(logger).to receive(:unknown).with("msg", "prog", key: "val")
    subject[:logger] = logger
    subject.unknown "msg", "prog", key: "val"
  end

  it "#fatal" do
    logger = double("logger")
    expect(logger).to(receive(:fatal).with(nil, nil, key: "val").and_yield { "progname" })
    subject[:logger] = logger
    subject.fatal(key: "val") { "progname" }
  end

  it "#truncate" do
    logger = double("logger")
    expect(logger).to receive(:truncate)
    subject[:logger] = logger
    subject.truncate
  end
end
