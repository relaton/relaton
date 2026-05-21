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

  describe "errors guards" do # rubocop:disable Metrics/BlockLength
    let(:errors) { Hash.new(true) }

    it "sets @errors[:contributor] to false on success" do
      dp = Relaton::Oasis::DataParser.new(node, errors)
      allow(dp).to receive(:publisher_oasis).and_return([:oasis])
      allow(dp).to receive(:parse_authorizer).and_return([])
      allow(dp).to receive(:parse_editorialgroup_contributor).and_return([])
      allow(dp).to receive(:parse_chairs).and_return([])
      allow(dp).to receive(:parse_editors).and_return([])
      dp.parse_contributor
      expect(errors[:contributor]).to be false
    end

    it "sets @errors[:editors] to false via parse_editors_from_text" do
      html = <<~HTML
        <details>
          <summary><div><h2>Title</h2></div></summary>
          <div><div><div class="standard__grid--cite-as">
            <p><em>Edited by John Doe.</em></p>
          </div></div></div>
        </details>
      HTML
      dp = Relaton::Oasis::DataParser.new(
        Nokogiri::HTML(html).at("//details"), errors,
      )
      allow(dp).to receive(:page).and_return(nil)
      dp.send(:parse_editors_from_text)
      expect(errors[:editors]).to be false
    end

    it "keeps @errors[:chairs] true when page is nil" do
      dp = Relaton::Oasis::DataParser.new(node, errors)
      allow(dp).to receive(:page).and_return(nil)
      dp.send(:parse_chairs)
      expect(errors[:chairs]).to be true
    end

    it "keeps @errors[:editors] true when page is nil and no text" do
      dp = Relaton::Oasis::DataParser.new(node, errors)
      allow(dp).to receive(:page).and_return(nil)
      dp.send(:parse_editors)
      expect(errors[:editors]).to be true
    end

    it "sets @errors[:docid] to false on success" do
      dp = Relaton::Oasis::DataParser.new(node, errors)
      dp.parse_docid
      expect(errors[:docid]).to be false
    end

    it "sets @errors[:doctype] to false on success" do
      dp = Relaton::Oasis::DataParser.new(node, errors)
      dp.parse_doctype
      expect(errors[:doctype]).to be false
    end

    it "sets @errors[:technology_area] true when no areas" do
      test_obj = Object.new
      test_obj.instance_variable_set(:@errors, errors)
      test_obj.extend Relaton::Oasis::DataParserUtils
      test_obj.send(:parse_technology_area, node)
      expect(errors[:technology_area]).to be true
    end

    it "sets @errors[:technology_area] to false on success" do
      html = <<~HTML
        <details>
          <summary><div><div>
            <ul class="technology-areas__list">
              <li><a href="#">Cloud</a></li>
            </ul>
          </div><h2>Title</h2></div></summary>
        </details>
      HTML
      n = Nokogiri::HTML(html).at("//details")
      test_obj = Object.new
      test_obj.instance_variable_set(:@errors, errors)
      test_obj.extend Relaton::Oasis::DataParserUtils
      test_obj.send(:parse_technology_area, n)
      expect(errors[:technology_area]).to be false
    end
  end

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

  describe "#parse_editors" do
    it "skips contributor paragraphs whose text is a URI" do
      html = <<~HTML
        <html><body>
          <p>Editor(s):</p>
          <p class="Contributor">William Cox</p>
          <p class="Contributor">http://docs.oasis-open.org/ns/emix/2011/06/power/resource</p>
          <p class="Title">EMIX</p>
        </body></html>
      HTML
      dp = Relaton::Oasis::DataParser.new(node)
      allow(dp).to receive(:page).and_return(Nokogiri::HTML(html))
      result = dp.send(:parse_editors)
      expect(result.size).to eq 1
      expect(result.first.person.name.forename.first.content).to eq "William"
    end

    it "skips contributor paragraphs that start with a bullet" do
      html = <<~HTML
        <html><body>
          <p>Editor(s):</p>
          <p class="Contributor">Hal Lockhart</p>
          <p class="Contributor">·         eXtensible Access Control Markup Language</p>
          <p class="Title">XACML</p>
        </body></html>
      HTML
      dp = Relaton::Oasis::DataParser.new(node)
      allow(dp).to receive(:page).and_return(Nokogiri::HTML(html))
      result = dp.send(:parse_editors)
      expect(result.size).to eq 1
      expect(result.first.person.name.forename.first.content).to eq "Hal"
    end

    it "includes ligature text adjacent to a Cloudflare-obfuscated email" do
      # Cloudflare's email scanner leaves non-ASCII characters (here the Latin
      # "fl" ligature U+FB02) outside the data-cfemail span; the span only
      # encodes the ASCII tail "orian.mueller02@sap.com".
      html = <<~HTML
        <html><body>
          <p>Editor(s):</p>
          <p class="Contributor">Florian M&uuml;ller (<a href="/cdn-cgi/l/email-protection#56303a39">&#64258;<span class="__cf_email__" data-cfemail="026d706b636c2c6f77676e6e67703230427163722c616d6f">[email&#160;protected]</span></a>), <a href="http://www.sap.com/">SAP</a></p>
          <p class="Title">CMIS</p>
        </body></html>
      HTML
      dp = Relaton::Oasis::DataParser.new(node)
      allow(dp).to receive(:page).and_return(Nokogiri::HTML(html))
      result = dp.send(:parse_editors)
      expect(result.size).to eq 1
      expect(result.first.person.email).to eq ["florian.mueller02@sap.com"]
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
