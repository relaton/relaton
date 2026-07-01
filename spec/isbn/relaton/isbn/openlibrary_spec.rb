describe Relaton::Isbn::OpenLibrary do
  context "get" do
    it "success" do
      expect do
        expect(described_class).to receive(:request_api).with("9780120644810").and_return :doc
        bib = double "bib", docidentifier: [double("id", content: "id")]
        expect(Relaton::Isbn::Parser).to receive(:parse).with(:doc).and_return bib
        expect(described_class.get("ISBN 9780120644810")).to eq bib
      end.to output(include("[relaton-isbn] INFO: (ISBN 9780120644810) Fetching from OpenLibrary ...",
                            "[relaton-isbn] INFO: (ISBN 9780120644810) Found: `id`")).to_stderr_from_any_process
    end

    it "not found" do
      expect do
        expect(described_class).to receive(:request_api).with("9780120644810").and_return nil
        expect(Relaton::Isbn::Parser).not_to receive(:parse)
        expect(described_class.get("ISBN 9780120644810")).to be_nil
      end.to output(include("[relaton-isbn] INFO: (ISBN 9780120644810) Not found.")).to_stderr_from_any_process
    end

    it "incorrect ISBN" do
      expect do
        expect(described_class).not_to receive(:request_api)
        expect(described_class.get("ISBN")).to be_nil
      end.to output(include("[relaton-isbn] INFO: (ISBN) Incorrect ISBN.")).to_stderr_from_any_process
    end
  end

  context "request_api" do
    let(:resp) { double "response" }

    before do
      expect(URI).to receive(:parse).with("http://openlibrary.org/api/volumes/brief/isbn/9780120644810.json")
        .and_return :uri
    end

    it "success" do
      expect(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return true
      expect(resp).to receive(:body).and_return '{"records": {"/books/OL21119585M": {"publishDates": ["2008"]}}}'
      expect(Net::HTTP).to receive(:get_response).with(:uri).and_return resp
      expect(described_class.request_api("9780120644810")).to eq({ "publishDates" => ["2008"] })
    end

    it "unsuccess" do
      expect(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return false
      expect(Net::HTTP).to receive(:get_response).with(:uri).and_return resp
      expect(described_class.request_api("9780120644810")).to be_nil
    end

    it "no records" do
      expect(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return true
      expect(resp).to receive(:body).and_return '{"records": {}}'
      expect(Net::HTTP).to receive(:get_response).with(:uri).and_return resp
      expect(described_class.request_api("9780120644810")).to be_nil
    end
  end
end
