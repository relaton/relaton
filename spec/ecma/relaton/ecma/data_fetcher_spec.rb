require "relaton/ecma/data_fetcher"

describe Relaton::Ecma::DataFetcher do
  subject { described_class.new("data", "yaml") }

  it "#fetch" do
    expect(subject).to receive(:html_index).with("standards")
    expect(subject).to receive(:html_index).with("technical-reports")
    expect(subject).to receive(:html_index).with("mementos")
    expect(subject.index).to receive(:save)
    subject.fetch
  end

  context "#html_index" do
    before do
      doc = Nokogiri::HTML <<~HTML
        <html>
          <body>
            <ul>
              <li>
                <span>
                  <a href="https://www.ecma-international.org/publications/standards/Ecma-6.htm">ECMA-6</a>
                </span>
                <span>1st edition (June 1964)</span>
              </li>
            </ul>
            <div class="entry-content-wrapper">
              <div><section><div><p>2023</p></div></section></div>
              <div><section><div><p>January 2023</p></div></section></div>
              <div><section><div><p><a>Download</a></p></div></section></div>
            </div>
          </body>
        </html>
      HTML
      expect(subject.agent).to receive(:get).with("#{described_class::URL}standards/").and_return doc
    end

    it "success" do
      expect(subject).to receive(:parse_page).twice
      subject.html_index "standards"
    end

    it "error" do
      expect(subject).to receive(:parse_page).and_raise StandardError, "error"
      expect(subject).to receive(:parse_page)
      expect { subject.html_index "standards" }.to output(/error/).to_stderr_from_any_process
    end
  end

  context "#parse_page" do
    let(:hit) { double :hit, text: "text" }

    before do
      expect(subject).to receive(:write_file).with(:item)
    end

    it "with href" do
      parser = double :parser
      expect(parser).to receive(:parse).with(no_args).and_return [:item]
      expect(Relaton::Ecma::DataParser).to receive(:new).with(hit, kind_of(Hash)).and_return parser
      subject.parse_page hit
    end
  end

  context "#index" do
    it "is the pubid index-v2, on the producer side too" do
      # Without `pubid_class:` here, FileIO#save calls `to_hash` only for
      # instances of it, so the crawl writes v1-shaped rows under a v2 name.
      expect(Relaton::Index).to receive(:find_or_create).with(
        :ecma, file: "index-v2.yaml", pubid_class: ::Pubid::Ecma::Identifier
      )
      subject.index
    end
  end

  context "#index_id" do
    def item(content, edition: nil, volume: nil)
      docid = Relaton::Ecma::Docidentifier.new content: content
      extent = if volume
                 locality = Relaton::Bib::Locality.new type: "volume", reference_from: volume
                 [Relaton::Bib::Extent.new(locality: [locality])]
               else
                 []
               end
      Relaton::Ecma::ItemData.new(
        docidentifier: [docid], extent: extent,
        edition: (Relaton::Bib::Edition.new(content: edition) if edition),
      )
    end

    it "carries the number, the edition and the volume" do
      id = subject.index_id item("ECMA-269", edition: "3", volume: "1")
      expect(id).to be_a Pubid::Ecma::Identifier
      expect(id.number).to eq "269"
      expect(id.edition).to eq "3"
      expect(id.volume).to eq "1"
      expect(id.to_s).to eq "ECMA-269 ed3 vol1"
    end

    it "carries neither for a document that has neither" do
      id = subject.index_id item("ECMA MEM/2021")
      expect(id.edition).to be_nil
      expect(id.volume).to be_nil
      expect(id.to_s).to eq "ECMA MEM/2021"
    end

    it "leaves the document's own docidentifier bare" do
      bib = item("ECMA-269", edition: "3", volume: "1")
      subject.index_id bib
      expect(bib.docidentifier[0].content).to eq "ECMA-269"
      expect(bib.docidentifier[0].pubid.edition).to be_nil
    end

    it "returns nil for a docid pubid rejects" do
      expect(subject.index_id(item("ECMA TR-27"))).to be_nil
    end
  end

  context "an unparseable docid" do
    let(:bib) do
      docid = Relaton::Ecma::Docidentifier.new content: "ECMA TR-27"
      Relaton::Ecma::ItemData.new docnumber: "TR-27", docidentifier: [docid]
    end

    it "is recorded in @errors, skipped from the index, and still written" do
      expect(File).to receive(:write).with("data/ecma-tr-27.yaml", kind_of(String), encoding: "UTF-8")
      expect(subject.index).not_to receive(:add_or_update)
      subject.write_file bib
      expect(subject.instance_variable_get(:@errors)["ECMA TR-27"])
        .to eq "Unparseable primary id `ECMA TR-27` was not indexed (data/ecma-tr-27.yaml)"
    end

    it "reaches report_errors, which opens the GitHub issue" do
      allow(File).to receive(:write)
      subject.write_file bib
      expect(subject).to receive(:log_error)
        .with("Unparseable primary id `ECMA TR-27` was not indexed (data/ecma-tr-27.yaml)")
      subject.report_errors
    end
  end

  context "#write_file" do
    let(:bib) do
      docid = Relaton::Ecma::Docidentifier.new content: "ECMA TR/27"
      ed = Relaton::Bib::Edition.new content: "1.2"
      locality = Relaton::Bib::Locality.new type: "volume", reference_from: "1"
      extent = Relaton::Bib::Extent.new locality: [locality]
      Relaton::Ecma::ItemData.new docnumber: "TR/27", docidentifier: [docid], edition: ed, extent: [extent]
    end

    it "default output dir & YAML format" do
      expect(File).to receive(:write).with("data/ecma-tr-27-1-2-1.yaml", match(/ECMA TR\/27/), encoding: "UTF-8")
      expect(subject.index).to receive(:add_or_update) do |id, file|
        expect(id).to be_a Pubid::Ecma::Identifiers::TechnicalReport
        expect(id.to_s).to eq "ECMA TR/27 ed1.2 vol1"
        expect(file).to eq "data/ecma-tr-27-1-2-1.yaml"
      end
      subject.write_file bib
    end

    it "custom output dir & XML format" do
      expect(bib).to receive(:to_xml).with(bibdata: true).and_return :xml
      df = described_class.new "dir", "xml"
      expect(File).to receive(:write).with("dir/ecma-tr-27-1-2-1.xml", :xml, encoding: "UTF-8")
      df.write_file bib
    end

    it "BibXML format" do
      df = described_class.new "data", "bibxml"
      expect(File).to receive(:write).with("data/ecma-tr-27-1-2-1.xml", /anchor="TR\/27"/, encoding: "UTF-8")
      df.write_file bib
    end

    it "gives a colliding, DISTINCT docid a file of its own" do
      # "ECMA TR/27" and "ECMA TR-27" both sanitize to ecma-tr-27-1-2-1.yaml.
      # The second document used to be dropped outright.
      other_docid = Relaton::Ecma::Docidentifier.new content: "ECMA TR-27"
      other = Relaton::Ecma::ItemData.new(
        docnumber: "TR-27", docidentifier: [other_docid],
        edition: bib.edition, extent: bib.extent
      )
      written = []
      allow(File).to receive(:write) { |f, *| written << f }
      allow(subject.index).to receive(:add_or_update)

      subject.write_file bib
      expect { subject.write_file other }
        .to output(/Duplicate file/).to_stderr_from_any_process

      expect(written.uniq.size).to eq 2
      expect(written.first).to eq "data/ecma-tr-27-1-2-1.yaml"
    end

    it "still skips a repeat of a docid that was already disambiguated" do
      # Regression: gating the duplicate check on `file != filename(bib)` made
      # this branch unreachable, because a disambiguated path stays different
      # from the plain one forever — so the repeat overwrote its own file
      # instead of being skipped.
      other_docid = Relaton::Ecma::Docidentifier.new content: "ECMA TR-27"
      other = Relaton::Ecma::ItemData.new(
        docnumber: "TR-27", docidentifier: [other_docid],
        edition: bib.edition, extent: bib.extent
      )
      allow(subject.index).to receive(:add_or_update)
      allow(File).to receive(:write)

      subject.write_file bib      # takes data/ecma-tr-27-1-2-1.yaml
      subject.write_file other    # disambiguated onto its own path

      expect(File).not_to receive(:write)
      expect { subject.write_file other } # same docid again -> skip
        .to output(/Duplicate file/).to_stderr_from_any_process
    end

    it "warns if file exists" do
      subject.instance_variable_set :@files, ["data/ecma-tr-27-1-2-1.yaml"]
      expect(File).not_to receive(:write).with("data/ecma-tr-27-1-2-1.yaml", :yaml, encoding: "UTF-8")
      expect do
        subject.write_file bib
      end.to output(/Duplicate file data\/ecma-tr-27-1-2-1.yaml/).to_stderr_from_any_process
    end
  end
end
