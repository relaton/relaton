# encoding: UTF-8

require "relaton/cie/data_fetcher"

RSpec.describe Relaton::Cie::DataFetcher do
  context "instance methods" do
    let(:hit) do
      Nokogiri::HTML(<<~HTML).at("li")
        <li data-product="2930375">
          <div class="cover product_image">
            <p class="notice version-notice">
                <span class="version powertip" data-powertiptarget="current_flag_content" title="This is the most recent version of this document."><i class="current-version ss-icon"></i>MOST RECENT</span>
            </p>
            <a href="https://store.accuristech.com/standards/cie-iso-8995-1-2025-en?product_id=2930375">
              <img src="//images.techstreet.com/coverart/3/7/5/2930375.jpg">      </a>
          </div><!-- .cover.product_image //-->
          <div class="product_detail">
            <h3>
              <a href="https://store.accuristech.com/standards/cie-iso-8995-1-2025-en?product_id=2930375">
                <span class="highlight">CIE</span> <span class="highlight">ISO</span> <span class="highlight">8995-1:2025(en)</span><span class="ss-icon">▹</span>
              </a>
            </h3>
            <h4>Light and lighting - Lighting of work places - Part 1: Indoor</h4>
            <p class="pub_date"><span>standard</span> by <span class="publisher_name">Commission Internationale de L'Eclairage</span>, 01/01/2025.
            </p>
            <p class="pub_date">
              <span>Languages: </span>
              English
            </p>
            <p class="pub_date">
              <span>Historical Editions:</span>
              <a href="https://store.accuristech.com/standards/cie-s-008-e-2001-iso-8995-1-2002-e?product_id=1529685">CIE S 008/E:2001 (ISO 8995-1:2002(E))</a>
            </p>
          </div><!-- .product_detail //-->
        </li>
      HTML
    end

    subject { described_class.new "data", "yaml" }

    let(:agent) { instance_double(Relaton::Cie::BrowserAgent, quit: nil) }

    before { allow(subject).to receive(:agent).and_return(agent) }

    context "#fetch" do
      it "collects hits, processes them, then saves the index once" do
        hits = [double("hit1"), double("hit2")]
        expect(subject).to receive(:collect_hits).and_return(hits)
        expect(subject).to receive(:process_hits).with(hits)
        expect(subject.index).to receive(:save).once
        subject.fetch
      end
    end

    context "#collect_hits (Phase 1, serial listing)" do
      let(:url) { "https://www.techstreet.com/cie/searches/31156444?page=1&per_page=100" }

      before { allow(subject).to receive(:time_req).and_yield }

      it "follows next_page and accumulates every hit across pages" do
        page1 = Nokogiri::HTML <<~HTML
          <html><body>
            <ol><li data-product="A"><h3><a href="/a">CIE 001-1980</a></h3></li></ol>
            <a class="next_page" href="/cie/standards?page=2">Next</a>
          </body></html>
        HTML
        page2 = Nokogiri::HTML <<~HTML
          <html><body>
            <ol><li data-product="B"><h3><a href="/b">CIE 002-1981</a></h3></li></ol>
          </body></html>
        HTML
        expect(agent).to receive(:get).with(url).and_return page1
        expect(agent).to receive(:get)
          .with("https://www.techstreet.com/cie/standards?page=2").and_return page2

        hits = subject.collect_hits
        expect(hits.map { |h| h["data-product"] }).to eq %w[A B]
      end

      it "stops at the last page" do
        page = Nokogiri::HTML <<~HTML
          <html><body>
            <ol><li data-product="A"><h3><a href="/a">CIE 001-1980</a></h3></li></ol>
          </body></html>
        HTML
        expect(agent).to receive(:get).with(url).and_return page
        expect(subject.collect_hits.size).to eq 1
      end
    end

    context "#process_hits (Phase 2, parallel detail fetch)" do
      # A minimal hit whose primary code is derived from its h3/a text, plus a
      # blank detail page (the fetch_* extractors all degrade to empty/nil on a
      # bare document, so no fixture is needed here).
      def hit_for(code, href)
        Nokogiri::HTML(<<~HTML).at("li")
          <li data-product="#{code}"><h3><a href="#{href}">#{code}</a></h3></li>
        HTML
      end

      let(:hits) do
        (1..6).map { |i| hit_for(format("CIE %03d-1980", i), "/cie/standards/#{i}") }
      end

      # Drive #process_hits at concurrency `n` against a stubbed agent factory
      # (one double per worker) and return [recorded [id, pos] writes, agents].
      def run_pool(n, hits)
        fetcher = described_class.new "data", "yaml"
        allow(described_class).to receive(:concurrency).and_return(n)
        allow(fetcher).to receive(:time_req).and_yield # skip real pacing sleeps

        agents = []
        amutex = Mutex.new
        allow(fetcher).to receive(:build_agent) do
          a = instance_double(Relaton::Cie::BrowserAgent, quit: nil)
          allow(a).to receive(:get).and_return(Nokogiri::HTML("<html><body></body></html>"))
          amutex.synchronize { agents << a }
          a
        end

        written = []
        allow(fetcher).to receive(:write_file) { |item, pos| written << [item.docidentifier[0].content, pos] }

        fetcher.process_hits(hits)
        [written, agents]
      end

      it "processes every hit and produces the same record set as a serial run" do
        serial, = run_pool(1, hits)
        parallel, agents = run_pool(5, hits)

        expected = (1..6).map { |i| format("CIE %03d-1980", i) }
        expect(parallel.map(&:first).sort).to eq expected.sort
        # Output is order-independent: the parallel record set equals the serial one.
        expect(parallel.map(&:first).sort).to eq serial.map(&:first).sort
        # One agent per worker, and every created agent is quit.
        expect(agents.size).to eq 5
        agents.each { |a| expect(a).to have_received(:quit) }
      end

      it "launches no browser when there are no hits" do
        allow(described_class).to receive(:concurrency).and_return(3)
        expect(subject).not_to receive(:build_agent)
        subject.process_hits([])
      end

      it "fails fast and quits already-built agents when a browser fails to launch" do
        allow(described_class).to receive(:concurrency).and_return(3)
        built = []
        call = 0
        allow(subject).to receive(:build_agent) do
          call += 1
          raise "chrome launch failed" if call == 3

          instance_double(Relaton::Cie::BrowserAgent, quit: nil).tap { |a| built << a }
        end

        expect { subject.process_hits([hit_for("CIE 001-1980", "/a")]) }
          .to raise_error("chrome launch failed")
        expect(built.size).to eq 2
        built.each { |a| expect(a).to have_received(:quit) }
      end
    end

    context "#parse_page" do
      let(:doc) { Nokogiri::HTML File.read("fixtures/doc.html") }

      before do
        expect(subject).to receive(:time_req).and_yield
      end

      it do
        link = "https://store.accuristech.com/standards/cie-iso-8995-1-2025-en?product_id=2930375"
        expect(agent).to receive(:get).with(link).and_return doc
        item = nil
        expect(subject).to receive(:write_file) { |i| item = i }
        subject.parse_page hit
        expect(item).to be_instance_of Relaton::Cie::ItemData
        expect(item.id).to eq "CIEISO899512025"
        expect(item.type).to eq "standard"
        expect(item.source.first).to be_instance_of Relaton::Bib::Uri
        expect(item.docnumber).to eq "8995-1:2025"
        expect(item.docidentifier.first).to be_instance_of Relaton::Bib::Docidentifier
        expect(item.title.first).to be_instance_of Relaton::Bib::Title
        expect(item.abstract.first).to be_instance_of Relaton::Bib::Abstract
        expect(item.date.first).to be_instance_of Relaton::Bib::Date
        expect(item.edition).to be_instance_of Relaton::Bib::Edition
        expect(item.contributor.first).to be_instance_of Relaton::Bib::Contributor
        expect(item.relation.first).to be_instance_of Relaton::Bib::Relation
        expect(item.language).to eq "en"
        expect(item.script).to eq "Latn"
        expect(item.ext).to be_instance_of Relaton::Cie::Ext
        expect(item.ext.doctype).to be_instance_of Relaton::Bib::Doctype
        expect(item.ext.flavor).to eq "cie"
        expect(item.ext.schema_version).to eq Relaton.schema_versions["relaton-model-cie"]
      end

      it "raise error" do
        expect(agent).to receive(:get).and_raise StandardError
        expect { subject.parse_page hit }.to output(
          /https:\/\/store\.accuristech\.com\/standards\/cie-iso-8995-1-2025-en\?product_id=2930375/
        ).to_stderr_from_any_process
      end
    end

    it "#fetch_link" do
      source = subject.fetch_source "https://www.techstreet.com/cie/standards/001-1980"
      expect(source).to be_instance_of Array
      expect(source.first).to be_instance_of Relaton::Bib::Uri
      expect(source.first.content.to_s).to eq "https://www.techstreet.com/cie/standards/001-1980"
      expect(source.first.type).to eq "src"
    end

    context "#fetch_docid" do
      it "one code & ISBN" do
        doc = Nokogiri::HTML <<~HTML
          <html>
            <body>
              <div class="product-details__row">
                <h3>ISBN(s):</h3>
                <span>9783902842138</span>
              </div>
            </body>
          </html>
        HTML
        expect(subject).to receive(:parse_code).with(:hit, doc).and_return ["CIE 001-1980", nil]
        docid = subject.fetch_docid :hit, doc
        expect(docid).to be_instance_of Array
        expect(docid.size).to eq 2
        expect(docid.first).to be_instance_of Relaton::Bib::Docidentifier
        expect(docid.first.content).to eq "CIE 001-1980"
        expect(docid.first.type).to eq "CIE"
        expect(docid.first.primary).to be true
        expect(docid.last.content).to eq "9783902842138"
        expect(docid.last.type).to eq "ISBN"
      end

      it "two codes" do
        doc = Nokogiri::HTML "<html><body></body></html>"
        expect(subject).to receive(:parse_code).with(:hit, doc).and_return ["CIE S 014-1/E:2006", "ISO 10527:2007"]
        docid = subject.fetch_docid :hit, doc
        expect(docid).to be_instance_of Array
        expect(docid.size).to eq 2
        expect(docid.first).to be_instance_of Relaton::Bib::Docidentifier
        expect(docid.first.content).to eq "CIE S 014-1/E:2006"
        expect(docid.first.type).to eq "CIE"
        expect(docid.first.primary).to be true
        expect(docid.last.content).to eq "ISO 10527:2007"
        expect(docid.last.type).to eq "ISO"
      end
    end

    context "#fetch_title" do
      it "h1" do
        doc = Nokogiri::HTML <<~HTML
          <html>
            <body>
              <hgroup><h1>Title</h1></hgroup>
            </body>
          </html>
        HTML
        title = subject.fetch_title doc
        expect(title[0]).to be_instance_of Relaton::Bib::Title
        expect(title.size).to eq 2
        expect(title.first).to be_instance_of Relaton::Bib::Title
        expect(title.first.content).to eq "Title"
        expect(title.first.type).to eq "title-main"
        expect(title.last).to be_instance_of Relaton::Bib::Title
        expect(title.last.content).to eq "Title"
        expect(title.last.type).to eq "main"
      end

      it "h2" do
        doc = Nokogiri::HTML <<~HTML
          <html>
            <body>
              <hgroup><h2>Title</h2></hgroup>
            </body>
          </html>
        HTML
        title = subject.fetch_title doc
        expect(title[0]).to be_instance_of Relaton::Bib::Title
        expect(title.size).to eq 2
        expect(title.first.content).to eq "Title"
      end

      it "empty" do
        doc = Nokogiri::HTML "<html><body></body></html>"
        title = subject.fetch_title doc
        expect(title).to eq []
      end
    end

    context "#fetch_abstract" do
      it do
        doc = Nokogiri::HTML <<~HTML
          <html>
            <body>
              <div class="description"> Description </div>
            </body>
          </html>
        HTML
        abstract = subject.fetch_abstract doc
        expect(abstract).to be_instance_of Array
        expect(abstract.size).to eq 1
        expect(abstract.first).to be_instance_of Relaton::Bib::Abstract
        expect(abstract.first.content).to eq "Description"
        expect(abstract.first.language).to eq "en"
        expect(abstract.first.script).to eq "Latn"
      end
    end

    context "#fetch_date" do
      shared_examples "fetch date" do |source, expected|
        it do
          doc = Nokogiri::HTML <<~HTML
            <html>
              <body>
                <div class="product-details__row">
                  <h3>Published:</h3>
                  <span>#{source}</span>
                </div>
              </body>
            </html>
          HTML
          date = subject.fetch_date doc
          expect(date).to be_instance_of Array
          expect(date.size).to eq 1
          expect(date.first).to be_instance_of Relaton::Bib::Date
          expect(date.first.type).to eq "published"
          expect(date.first.at.to_s).to eq expected
        end
      end

      it_behaves_like "fetch date", " 1992", "1992"
      it_behaves_like "fetch date", " 02/22/2023", "2023-02-22"
    end

    it "#fetch_edition" do
      doc = Nokogiri::HTML <<~HTML
        <html>
          <body>
            <div class="product-details__row">
              <h3>Edition:</h3>
              <span>1st</span>
            </div>
          </body>
        </html>
      HTML
      expect(subject.fetch_edition(doc).content).to eq "1"
    end

    context "#fetch_contributor" do
      it do
        doc = Nokogiri::HTML <<~HTML
          <html>
            <body>
              <hgroup>
                <p class="pub_date">Published: 1992</p>
                <p>Ruggaber, B., Vollrath, T., Krüger, U., Blattner, P. and Gerloff, T.</p>
              </hgroup>
            </body>
          </html>
        HTML
        contribs = subject.fetch_contributor doc
        expect(contribs).to be_instance_of Array
        expect(contribs.size).to eq 6
        expect(contribs.first).to be_instance_of Relaton::Bib::Contributor
        expect(contribs.first.person).to be_instance_of Relaton::Bib::Person
        expect(contribs.first.person.name.surname.content).to eq "Ruggaber"
        expect(contribs.first.person.name.forename[0].initial).to eq "B"
        expect(contribs.first.role.first.type).to eq "author"
        expect(contribs.last.organization).to be_instance_of Relaton::Bib::Organization
        expect(contribs.last.organization.name.first.content).to eq "Commission Internationale de L'Eclairage"
        expect(contribs.last.role.first.type).to eq "publisher"
      end

      it do
        doc = Nokogiri::HTML <<~HTML
          <html>
            <body>
              <hgroup>
                <p>Vali, K.; Au-Yeung, W-T. M.; Kaye, J.; Pierson, C.</p>
              </hgroup>
            </body>
          </html>
        HTML
        contribs = subject.fetch_contributor doc
        expect(contribs).to be_instance_of Array
        expect(contribs.size).to eq 6
      end
    end

    it "#fetch_relation" do
      doc = Nokogiri::HTML <<~HTML
        <html>
          <body>
            <section class="history">
              <ol>
                <li class="selected-product"><a><h3>CIE 001-1980</h3></a></li>
                <li><a href="/cie/standards/001-1981">
                  <h3>CIE 001-1981</h3>
                  <p><time datetime="1992-01-01 00:00:00 +0000">January 1992</time>
                  <p><span class="title">Title</span></p>
                </a></li>
              </ol>
            </section>
          </body>
        </html>
      HTML
      relation = subject.fetch_relation doc
      expect(relation).to be_instance_of Array
      expect(relation.size).to eq 1
    end

    it "#fetch_doctype" do
      doctype = subject.fetch_doctype
      expect(doctype).to be_instance_of Relaton::Bib::Doctype
      expect(doctype.content).to eq "document"
    end

    context "#parse_code" do
      it "one code" do
        expect(subject).to receive(:primary_code).with("CIE ISO 8995-1:2025(en)", nil).and_return "CIE ISO 8995-1:2025(en)"
        code = subject.parse_code hit
        expect(code).to be_instance_of Array
        expect(code.size).to eq 2
        expect(code.first).to eq "CIE ISO 8995-1:2025(en)"
        expect(code.last).to be_nil
      end

      it "two codes" do
        hit = Nokogiri::HTML(<<~HTML).at("li")
          <li data-product="CIE S 006.1/E-1998 (ISO 16508:1999)">
            <h3><a href="/cie/standards/S-014-1-E-2006">CIE S 006.1/E-1998 (ISO 16508:1999)</a></h3>
          </li>
        HTML
        expect(subject).to receive(:primary_code).with("CIE S 006.1/E-1998", nil).and_return "CIE S 006.1/E-1998"
        code = subject.parse_code hit
        expect(code).to be_instance_of Array
        expect(code.size).to eq 2
        expect(code.first).to eq "CIE S 006.1/E-1998"
        expect(code.last).to eq "ISO 16508:1999"
      end
    end

    context "#primary_code" do
      it "one code" do
        expect(subject).to receive(:parse_cie_code).with("CIE S 006.1/E-1998 ", nil, nil).and_return "CIE S 006.1/E-1998"
        expect(subject.primary_code("CIE S 006.1/E-1998 (ISO 16508:1999)")).to eq "CIE S 006.1/E-1998"
      end

      it "code from doc" do
        doc = Nokogiri::HTML <<~HTML
          <html>
            <body>
              <div class="product-details__row">
                <h3>Product Code(s):</h3>
                <span>x043-PP09, x043-PP09, x043-PP09</span>
              </div>
            </body>
          </html>
        HTML
        expect(subject.primary_code("", doc)).to eq "CIE x043-PP09"
      end

      it "code from braces" do
        expect(subject.primary_code("PERCEPTION OF ILLUMINATION WHITENESS (OP01, PAGES 1-7)")).to eq "CIE OP01 PAGES 1-7"
      end
    end

    context "#parse_cie_code" do
      it do
        expect(subject.parse_cie_code("CIE S 006.1/E-1998", nil)).to eq "CIE S 006.1/E-1998"
      end

      it "with addendum" do
        doc = Nokogiri::HTML <<~HTML
          <html>
            <body>
              <hgroup>
                <h2>Proceedings of CIE Centenary Conference "Towards a New Century of Light" Paris, France, 15-16 April 2013, Includes Addendum 1</h2>
              </hgroup>
            </body>
          </html>
        HTML
        expect(subject.parse_cie_code("CIE X038:2013", nil, doc)).to eq "CIE X038:2013 Add 1"
      end
    end

    it "#fetch_docnumber" do
      expect(subject.fetch_docnumber(hit)).to eq "8995-1:2025"
    end

    it "#index" do
      expect(subject.index).to be_instance_of Relaton::Index::Type
    end

    context "#write_file" do
      let(:bib) do
        docid = Relaton::Bib::Docidentifier.new(content: "CIE 001-1980", type: "CIE", primary: true)
        source = Relaton::Bib::Uri.new(type: "src", content: "https://www.techstreet.com/cie/standards/001-1980")
        Relaton::Cie::ItemData.new(docidentifier: [docid], source: [source])
      end

      before do
        expect(subject).to receive(:serialize).with(bib).and_return "content"
        expect(subject.index).to receive(:add_or_update).with(
          satisfy { |id| id.is_a?(::Pubid::Cie::Identifier) && id.to_s == "CIE 001-1980" },
          "data/cie-001-1980.yaml",
        )
        expect(File).to receive(:write).with("data/cie-001-1980.yaml", "content", encoding: "UTF-8")
      end

      it do
        subject.write_file bib
        expect(subject.instance_variable_get(:@files)).to include "data/cie-001-1980.yaml"
      end

      it "file exists" do
        subject.instance_variable_get(:@files) << "data/cie-001-1980.yaml"
        expect { subject.write_file bib }.to output(/File data\/cie-001-1980.yaml exists/).to_stderr_from_any_process
      end
    end

    context "#write_file with an unparseable id" do
      let(:bib) do
        docid = Relaton::Bib::Docidentifier.new(content: "CIE FOOBAR", type: "CIE", primary: true)
        source = Relaton::Bib::Uri.new(type: "src", content: "https://www.techstreet.com/cie/standards/foobar")
        Relaton::Cie::ItemData.new(docidentifier: [docid], source: [source])
      end

      it "writes the document but does not index the id" do
        expect(subject).to receive(:serialize).with(bib).and_return "content"
        expect(subject.index).not_to receive(:add_or_update)
        expect(File).to receive(:write).with(
          "data/cie-foobar.yaml", "content", encoding: "UTF-8"
        )
        expect { subject.write_file bib }
          .to output(/Unparseable id `CIE FOOBAR` was not indexed/).to_stderr_from_any_process
      end
    end

    context "#write_file duplicate output file (deterministic last-by-position winner)" do
      def bib_for(link)
        docid = Relaton::Bib::Docidentifier.new(content: "CIE 001-1980", type: "CIE", primary: true)
        source = Relaton::Bib::Uri.new(type: "src", content: link)
        Relaton::Cie::ItemData.new(docidentifier: [docid], source: [source])
      end

      before { allow(subject.index).to receive(:add_or_update) }

      it "drops an earlier-position write once a later position has claimed the file" do
        allow(subject).to receive(:serialize).and_return "later"
        # Later position (1) completes first; the earlier one (0) is superseded.
        expect(File).to receive(:write).with("data/cie-001-1980.yaml", "later", encoding: "UTF-8").once
        subject.write_file bib_for("https://x/later"), 1
        subject.write_file bib_for("https://x/earlier"), 0
      end

      it "lets a later position overwrite an earlier one that already wrote" do
        allow(subject).to receive(:serialize).and_return "earlier", "later"
        expect(File).to receive(:write).with("data/cie-001-1980.yaml", "earlier", encoding: "UTF-8").ordered
        expect(File).to receive(:write).with("data/cie-001-1980.yaml", "later", encoding: "UTF-8").ordered
        subject.write_file bib_for("https://x/earlier"), 0
        subject.write_file bib_for("https://x/later"), 1
      end
    end

    it "#to_xml" do
      bib = Relaton::Cie::ItemData.new
      expect(subject.to_xml(bib)).to include "<bibdata schema-version="
    end

    it "#to_yaml" do
      bib = Relaton::Cie::ItemData.new
      expect(subject.to_yaml(bib)).to include "---\nschema_version:"
    end

    it "#to_bibxml" do
      bib = Relaton::Cie::ItemData.new
      expect(subject.to_bibxml(bib)).to include "<reference"
    end

    context "#time_req" do
      let(:pacing) { Relaton::Cie::DataFetcher::Pacing.new }

      before { allow(pacing).to receive(:sleep) } # never actually sleep in specs

      it "paces via the worker's pacing and returns the block result" do
        expect(pacing).to receive(:throttle).and_call_original
        expect(subject.time_req(pacing) { :result }).to eq :result
      end

      it "retries a retriable error, backing the worker off first" do
        block = spy "block"
        expect(block).to receive(:call).and_raise SocketError
        expect(block).to receive(:call).and_return :result
        expect(pacing).to receive(:backoff).once
        expect(subject.time_req(pacing) { block.call }).to eq :result
      end

      it "treats a Cloudflare challenge as retriable" do
        block = spy "block"
        expect(block).to receive(:call).and_raise Relaton::Cie::BrowserAgent::ChallengeError
        expect(block).to receive(:call).and_return :result
        expect(subject.time_req(pacing) { block.call }).to eq :result
      end

      it "backs off on every attempt, then raises once retries are exhausted" do
        expect(pacing).to receive(:backoff).exactly(4).times
        expect { subject.time_req(pacing) { raise SocketError } }.to raise_error(SocketError)
      end

      it "doubles the gap on backoff, capped at the max" do
        pace = Relaton::Cie::DataFetcher::Pacing.new(base: 1, max: 4)
        expect { pace.backoff }.to change(pace, :gap).from(1).to(2)
        pace.backoff # -> 4
        expect { pace.backoff }.not_to change(pace, :gap) # capped
      end
    end
  end
end
