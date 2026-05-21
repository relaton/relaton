describe Relaton::Logger::FormatterString do
  context "#call" do
    it "no key" do
      expect(subject.call("DEBUG", "datetime", "progname", "msg")).to eq "[progname] DEBUG: msg\n"
    end

    it "key" do
      expect(subject.call("INFO", "datetime", "progname", "msg", key: "key")).to eq "[progname] INFO: (key) msg\n"
    end

    it "no progname" do
      expect(subject.call("WARN", "datetime", nil, "msg")).to eq "WARN: msg\n"
    end
  end
end
