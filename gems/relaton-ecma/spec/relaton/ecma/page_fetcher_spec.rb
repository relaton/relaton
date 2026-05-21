require "relaton/ecma/data_fetcher"

describe Relaton::Ecma::PageFetcher do
  subject { described_class.new }

  let(:agent) { subject.instance_variable_get :@agent }

  context "#get" do
    it "success" do
      expect(agent).to receive(:get).with(:url).and_return :doc

      expect(subject.get(:url)).to eq :doc
    end

    it "error" do
      expect(agent).to receive(:get).with(:url).and_raise StandardError, "error"
      expect(agent).to receive(:get).with(:url).and_return :doc

      expect do
        expect(subject.get(:url)).to eq :doc
      end.to output(/error/).to_stderr_from_any_process
    end
  end
end
