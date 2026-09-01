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

    # Every attempt failing used to fall out of `3.times`, whose value is the
    # receiver — so #get returned the Integer 3 and the caller reported the
    # transport error as `undefined method 'xpath' for an instance of Integer`.
    it "raises when every attempt fails" do
      url = "https://ecma-international.org/publications-and-standards/standards/ecma-370/"
      allow(subject).to receive(:sleep) # the ladder is real seconds; don't wait them out
      expect(agent).to receive(:get).with(url).exactly(described_class::RETRIES).times
        .and_raise StandardError, "error"

      expect do
        expect { subject.get(url) }
          .to raise_error Relaton::RequestError, "Could not access #{url}: error"
      end.to output(/error/).to_stderr_from_any_process
    end
  end
end
