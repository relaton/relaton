require "relaton/oasis/data_fetcher"

describe Relaton::Oasis::DataFetcher do
  subject { Relaton::Oasis::DataFetcher.new "data", "yaml" }

  it "initialize" do
    expect(subject.instance_variable_get(:@files)).to be_a Set
  end

  it "create output dir and run fetcher" do
    expect(FileUtils).to receive(:mkdir_p).with("dir")
    fetcher = double("fetcher")
    expect(fetcher).to receive(:fetch)
    expect(Relaton::Oasis::DataFetcher)
      .to receive(:new).with("dir", "xml").and_return(fetcher)
    Relaton::Oasis::DataFetcher.fetch output: "dir", format: "xml"
  end

  it "fetch" do
    agent = instance_double(Relaton::Oasis::BrowserAgent, quit: nil)
    doc = Nokogiri::HTML(<<~EOHTML)
      <details>
        <div><div><div class="standard__grid--cite-as">
          <p><strong>[ref1]</strong></p>
          <p><span><strong>[ref2]</strong></span></p>
        </div></div></div>
      </details>
    EOHTML
    expect(agent).to receive(:get).with("https://www.oasis-open.org/standards/").and_return(doc)
    allow(subject).to receive(:agent).and_return(agent)
    parser = double "parser"
    expect(parser).to receive(:parse).and_return(:bibitem)
    expect(subject).to receive(:save_doc).with(:bibitem).exactly(3).times
    expect(Relaton::Oasis::DataParser).to receive(:new)
      .with(kind_of(Nokogiri::XML::Element), kind_of(Hash), agent: agent)
      .and_return(parser)
    part_parser = double "part_parser"
    expect(part_parser).to receive(:parse).and_return(:bibitem).twice
    expect(Relaton::Oasis::DataPartParser).to receive(:new)
      .with(kind_of(Nokogiri::XML::Element), kind_of(Hash), agent: agent)
      .and_return(part_parser).twice
    index = subject.send(:index)
    expect(index).to receive(:save)
    subject.fetch
  end

  context "create_ext" do
    it "returns Ext with doctype, flavor, and technology_area" do
      test_obj = Object.new
      test_obj.extend Relaton::Oasis::DataParserUtils
      doctype = Relaton::Oasis::Doctype.new(content: "specification")
      tech_areas = ["Cloud", "Web-Services"]
      allow(test_obj).to receive(:parse_doctype).and_return(doctype)
      allow(test_obj).to receive(:parse_technology_area).and_return(tech_areas)

      ext = test_obj.create_ext

      expect(ext).to be_a Relaton::Oasis::Ext
      expect(ext.doctype).to eq doctype
      expect(ext.flavor).to eq "oasis"
      expect(ext.technology_area).to eq tech_areas
    end
  end

  context "index" do
    it "is created with the pubid class, so the rows serialize as v2" do
      expect(Relaton::Index).to receive(:find_or_create).with(
        :oasis, file: "index-v2.yaml",
        pubid_class: ::Pubid::Oasis::Identifier
      ).and_return(:index)
      expect(subject.send(:index)).to eq :index
    end
  end

  context "save doc" do
    let(:docid) { Relaton::Oasis::Docidentifier.new content: "OASIS amqp-core", primary: true }
    let(:title) { Relaton::Bib::Title.new(content: "AMQP Core") }
    let(:doc) { Relaton::Bib::ItemData.new(docidentifier: [docid], title: [title]) }
    let(:index) { subject.send(:index) }

    it "xml" do
      subject.instance_variable_set :@format, "xml"
      expect(File).to receive(:write).with("data/oasis-amqp-core.yaml", /bibdata/, encoding: "UTF-8")
      subject.send(:save_doc, doc)
      files = subject.instance_variable_get(:@files)
      expect(files).to include "data/oasis-amqp-core.yaml"
      expect(index.search("OASIS amqp-core").first[:file]).to eq "data/oasis-amqp-core.yaml"
    end

    it "indexes the pubid identifier, not the id string" do
      expect(File).to receive(:write)
      subject.send(:save_doc, doc)
      row = index.index.first
      expect(row[:id]).to be_a Pubid::Oasis::Identifiers::Standard
      expect(row[:id].to_s).to eq "OASIS amqp-core"
      expect(row[:id].root.number.to_s).to eq "amqp-core"
    end

    # The whole point of using @errors: report_errors turns a String value into
    # one line of the crawl's "Error fetching documents" GitHub issue.
    it "reports a parser-recorded id through report_errors" do
      subject.instance_variable_get(:@errors)["OASIS bad-id"] =
        "Unparseable primary id `OASIS bad-id` was not indexed"
      allow(subject).to receive(:log_error) # the boolean field keys
      expect(subject).to receive(:log_error)
        .with("Unparseable primary id `OASIS bad-id` was not indexed")
      subject.send(:report_errors)
    end

    it "records an unparseable id and skips the row, keeping the file" do
      unparseable = Relaton::Oasis::Docidentifier.new content: "amqp-core",
                                                      primary: true
      bad = Relaton::Bib::ItemData.new(docidentifier: [unparseable],
                                       title: [title])
      expect(File).to receive(:write)
      expect(index).not_to receive(:add_or_update)
      subject.send(:save_doc, bad)
      expect(subject.instance_variable_get(:@errors)["amqp-core"])
        .to match(/Unparseable primary id `amqp-core` was not indexed/)
    end

    it "yaml" do
      expect(File).to receive(:write).with(
        "data/oasis-amqp-core.yaml",
        /content: OASIS amqp-core/, encoding: "UTF-8"
      )
      subject.send(:save_doc, doc)
    end

    it "bibxml" do
      subject.instance_variable_set :@format, "bibxml"
      subject.instance_variable_set :@ext, "xml"
      expect(File).to receive(:write).with(
        "data/oasis-amqp-core.xml", /<reference/, encoding: "UTF-8"
      )
      subject.send(:save_doc, doc)
    end

    it "duplicate file warn" do
      subject.instance_variable_get(:@files) << "data/oasis-amqp-core.yaml"
      expect(File).to receive(:write).with(
        "data/oasis-amqp-core.yaml", /content: OASIS amqp-core/,
        encoding: "UTF-8"
      )
      expect do
        subject.send(:save_doc, doc)
      end.to output(/already exists/).to_stderr_from_any_process
    end
  end
end
