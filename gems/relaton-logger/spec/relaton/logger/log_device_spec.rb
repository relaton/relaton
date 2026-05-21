describe Relaton::Logger::LogDevice do
  context "#truncate" do
    let(:dev) { double("dev") }

    subject do
      expect(dev).to receive(:respond_to?).with(:write).and_return true
      expect(dev).to receive(:respond_to?).with(:close).and_return true
      expect(dev).to receive(:respond_to?).with(:path).and_return false
      described_class.new dev
    end

    it "respond to truncate" do
      expect(dev).to receive(:respond_to?).with(:truncate).and_return true
      expect(dev).to receive(:truncate)
      expect(dev).to receive(:rewind)
      subject.truncate
    end

    it "not respond to truncate" do
      expect(dev).to receive(:respond_to?).with(:truncate).and_return false
      expect(dev).not_to receive(:truncate)
      subject.truncate
    end

    context "add_log_header" do
      it "header" do
        subject.instance_variable_set :@header, true
        expect(dev).to receive(:size).and_return 0
        expect(dev).to receive(:write).with(/Logfile created on/)
        subject.add_log_header dev
      end

      it "no header" do
        subject.instance_variable_set :@header, false
        expect(dev).not_to receive(:write)
        subject.add_log_header dev
      end
    end
  end
end
