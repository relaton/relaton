# frozen_string_literal: true

require "relaton/oasis/data_fetcher"

RSpec.describe Relaton::Oasis::DataParserUtils do
  let(:node) do
    Nokogiri::HTML("<details><summary><div><h2>T</h2></div></summary></details>")
      .at("//details")
  end
  let(:parser) { Relaton::Oasis::DataParser.new(node) }
  let(:agent) { instance_double(Mechanize) }
  let(:url) { "https://example.com/doc.html" }

  describe "#retry_page" do
    it "returns page on success" do
      page = double("page")
      expect(parser).to receive(:sleep).with(1)
      expect(agent).to receive(:get).with(url).and_return(page)

      result = parser.send(:retry_page, url, agent)
      expect(result).to eq page
    end

    it "retries on timeout and returns page" do
      page = double("page")
      expect(parser).to receive(:sleep).with(1).exactly(2).times
      expect(agent).to receive(:get).with(url).once
        .and_raise(Errno::ETIMEDOUT)
      expect(agent).to receive(:get).with(url).once.and_return(page)

      result = parser.send(:retry_page, url, agent, 2)
      expect(result).to eq page
    end

    it "returns nil after exhausting retries" do
      expect(parser).to receive(:sleep).with(1).exactly(3).times
      expect(agent).to receive(:get).with(url).exactly(3).times
        .and_raise(Net::OpenTimeout)
      expect(Relaton::Oasis::Util).to receive(:error)
        .with(/Failed to get page/)

      result = parser.send(:retry_page, url, agent)
      expect(result).to be_nil
    end
  end

  describe "#parse_doctype" do
    def parser_with_text(cite_text)
      html = <<~HTML
        <details>
          <summary><div><h2>Title</h2></div></summary>
          <div><div><div class="standard__grid--cite-as">
            <p><em>#{cite_text}</em></p>
          </div></div></div>
        </details>
      HTML
      Relaton::Oasis::DataParser.new(Nokogiri::HTML(html).at("//details"))
    end

    it "returns 'specification' for Committee Specification" do
      dp = parser_with_text("OASIS Committee Specification 01")
      expect(dp.parse_doctype.content).to eq "specification"
    end

    it "returns 'specification' for Project Specification" do
      dp = parser_with_text("OASIS Project Specification 01")
      expect(dp.parse_doctype.content).to eq "specification"
    end

    it "returns 'memorandum' for Technical Memorandum" do
      dp = parser_with_text("Technical Memorandum")
      expect(dp.parse_doctype.content).to eq "memorandum"
    end

    it "returns 'resolution' for Technical Resolution" do
      dp = parser_with_text("Technical Resolution")
      expect(dp.parse_doctype.content).to eq "resolution"
    end

    it "returns 'standard' by default" do
      dp = parser_with_text("Some other text")
      expect(dp.parse_doctype.content).to eq "standard"
    end

    it "returns 'standard' when text is nil" do
      dp = Relaton::Oasis::DataParser.new(node)
      expect(dp.parse_doctype.content).to eq "standard"
    end
  end
end
