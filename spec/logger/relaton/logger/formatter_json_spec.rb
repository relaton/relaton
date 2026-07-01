describe Relaton::Logger::FormatterJSON do
  context "#call" do
    it "no key" do
      expect(subject.call("severity", "datetime", "progname", "msg")).to eq(
        "{\"prog\":\"progname\",\"message\":\"msg\",\"severity\":\"severity\"}\n",
      )
    end

    it "key" do
      expect(subject.call("severity", "datetime", "progname", "msg", key: "key")).to eq(
        "{\"prog\":\"progname\",\"message\":\"msg\",\"severity\":\"severity\",\"key\":\"key\"}\n",
      )
    end
  end
end
