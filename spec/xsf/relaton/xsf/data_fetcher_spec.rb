require "relaton/xsf/data_fetcher"

describe Relaton::Xsf::DataFetcher do
  context "instance methods" do
    subject { described_class.new "data", "yaml" }

    it "index" do
      expect(subject.index).to be_instance_of Relaton::Index::Type
    end

    it "#fetch" do
      agent = double "agent"
      resp = Nokogiri::XML <<~XML
        <html>
          <body>
            <pre>
              <a href="reference.XSF.XEP-0001.xml">reference.XSF.XEP-0001.xml</a>
            </pre>
          </body>
        </html>
      XML
      expect(agent).to receive(:get).with("https://xmpp.org/extensions/refs/").and_return resp
      expect(Mechanize).to receive(:new).and_return agent
      doc = double "doc", body: :body
      expect(agent).to receive(:get).with("reference.XSF.XEP-0001.xml").and_return doc
      expect(Relaton::Bib::Converter::BibXml).to receive(:to_item).with(:body).and_return :bib
      expect(subject).to receive(:save_doc).with(:bib)
      expect(subject.index).to receive(:save)
      subject.fetch
    end

    it "#fetch handles errors" do
      agent = double "agent"
      resp = Nokogiri::XML <<~XML
        <html>
          <body>
            <pre>
              <a href="reference.XSF.XEP-0001.xml">reference.XSF.XEP-0001.xml</a>
            </pre>
          </body>
        </html>
      XML
      expect(Mechanize).to receive(:new).and_return agent
      expect(agent).to receive(:get).with("https://xmpp.org/extensions/refs/").and_return resp
      expect(agent).to receive(:get).with("reference.XSF.XEP-0001.xml").and_raise(StandardError, "connection error")
      expect(subject).not_to receive(:save_doc)
      expect(subject.index).to receive(:save)
      expect { subject.fetch }.to output(/Failed to parse reference.XSF.XEP-0001.xml: connection error/).to_stderr_from_any_process
    end

    context "#save_doc" do
      let(:ext) { double("ext", flavor: nil) }
      let(:bib) do
        double "bibliographic item",
          docidentifier: [double(content: "XEP 0001", primary: true)],
          ext: ext, :"ext=" => nil
      end

      before do
        expect(ext).to receive(:flavor=).with("xsf")
        expect(subject).to receive(:serialize).with(bib).and_return :yaml
        expect(File).to receive(:write).with("data/xep-0001.yaml", :yaml, encoding: "UTF-8")
        # Indexed as a pubid now, not as the raw string. The docid is
        # "XEP 0001" with a space because that is what the published documents
        # carry -- the old double said "XEP-0001", which no XSF document uses
        # and which pubid rejects.
        expect(subject.index).to receive(:add_or_update)
          .with(an_instance_of(Pubid::Xsf::Identifiers::Xep), "data/xep-0001.yaml")
      end

      it "no duplications" do
        subject.save_doc bib
        expect(subject.instance_variable_get(:@files)).to eq Set["data/xep-0001.yaml"]
      end

      it "duplications" do
        subject.instance_variable_set :@files, Set["data/xep-0001.yaml"]
        expect { subject.save_doc bib }.to output(
          /already exists/,
        ).to_stderr_from_any_process
      end
    end

    context "#serialize" do
      let(:bib) { double "bibliographic item" }

      it "yaml" do
        expect(bib).to receive(:to_yaml).and_return :yaml
        expect(subject.to_yaml(bib)).to eq :yaml
      end

      it "xml" do
        expect(bib).to receive(:to_xml).with(bibdata: true).and_return :xml
        expect(subject.to_xml(bib)).to eq :xml
      end

      it "bibxml" do
        expect(bib).to receive(:to_rfcxml).and_return :bibxml
        expect(subject.to_bibxml(bib)).to eq :bibxml
      end
    end
  end
  describe "#add_to_index" do
    subject { described_class.new "data", "yaml" }

    # The crawled source carries two non-documents -- the repo's README and the
    # xep-xxxx template -- and Relaton::Index rejects the WHOLE index if one row
    # fails to deserialize, so they must never be indexed.
    # These two are expected on every crawl, so they are skipped SILENTLY --
    # recording them would file the same GitHub issue daily.
    Relaton::Xsf::DataFetcher::NON_DOCUMENTS.each do |docid|
      it "skips #{docid} without recording an error" do
        expect(subject.index).not_to receive(:add_or_update)
        subject.add_to_index docid, "data/x.yaml"
        expect(subject.instance_variable_get(:@errors)).to be_empty
      end
    end

    # Anything else pubid rejects is a surprise and must surface.
    it "records an unexpected unparseable docid" do
      expect(subject.index).not_to receive(:add_or_update)
      subject.add_to_index "XEP not-a-number", "data/x.yaml"
      expect(subject.instance_variable_get(:@errors)["XEP not-a-number"])
        .to match(/Unparseable primary id .* was not indexed/)
    end

    # report_errors is unusable unless the flavor overrides log_error --
    # Core::DataFetcher's raises. Without this, the first recorded error would
    # blow up the crawl instead of being reported.
    it "reports a recorded error instead of raising" do
      subject.add_to_index "XEP not-a-number", "data/x.yaml"
      expect(subject).to receive(:log_error).with(/Unparseable primary id/)
      expect { subject.report_errors }.not_to raise_error
    end

    it "indexes a real docid as a pubid" do
      expect(subject.index).to receive(:add_or_update)
        .with(an_instance_of(Pubid::Xsf::Identifiers::Xep), "data/xep-0001.yaml")
      subject.add_to_index "XEP 0001", "data/xep-0001.yaml"
    end
  end
end
