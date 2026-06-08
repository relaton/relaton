# frozen_string_literal: true

# require "open3"

RSpec.describe "Relaton Fetch" do
  describe "relaton fetch" do
    let(:db) { double("DB") }

    context do
      before do
        expect(Relaton::Cli).to receive(:relaton).and_return(db)
      end

      it "calls fetch" do
        expect(db).to receive(:fetch_std).with "ISO 2146", nil, :relaton_iso, type: "ISO"

        command = ["fetch", "--type", "ISO", "ISO 2146"]
        Relaton::Cli.start(command)
      end

      it "calls fetch with lowercase type" do
        expect(db).to receive(:fetch_std).with "ISO 2146", nil, :relaton_iso, type: "iso"

        command = ["fetch", "--type", "iso", "ISO 2146"]
        Relaton::Cli.start(command)
      end

      it "ignore cache" do
        expect(db).to receive(:fetch).with "ISO 2146", nil, no_cache: true

        command = ["fetch", "--no-cache", "ISO 2146"]
        Relaton::Cli.start(command)
      end

      it "calls fetch with publication date options" do
        expect(db).to receive(:fetch).with(
          "ISO 2146", nil,
          publication_date_before: Date.new(2008, 1, 1),
          publication_date_after: Date.new(2002, 1, 1)
        )

        command = ["fetch", "--publication-date-before", "2008",
                   "--publication-date-after", "2002", "ISO 2146"]
        Relaton::Cli.start(command)
      end

      it "calls fetch with YYYY-MM publication date options" do
        expect(db).to receive(:fetch).with(
          "ISO 2146", nil,
          publication_date_before: Date.new(2008, 6, 1),
          publication_date_after: Date.new(2002, 3, 1)
        )

        command = ["fetch", "--publication-date-before", "2008-06",
                   "--publication-date-after", "2002-03", "ISO 2146"]
        Relaton::Cli.start(command)
      end

      it "calls fetch with YYYY-MM-DD publication date options" do
        expect(db).to receive(:fetch).with(
          "ISO 2146", nil,
          publication_date_before: Date.new(2008, 6, 15),
          publication_date_after: Date.new(2002, 3, 10)
        )

        command = ["fetch", "--publication-date-before", "2008-06-15",
                   "--publication-date-after", "2002-03-10", "ISO 2146"]
        Relaton::Cli.start(command)
      end
    end

    context "publication date validation" do
      it "rejects invalid publication date format" do
        command = ["fetch", "--publication-date-before", "not-a-date", "ISO 2146"]
        expect { Relaton::Cli.start(command) }.to raise_error(
          ArgumentError, /Invalid --publication-date-before.*Expected YYYY/
        )
      end

      it "rejects out-of-range date components" do
        command = ["fetch", "--publication-date-after", "2008-13-01", "ISO 2146"]
        expect { Relaton::Cli.start(command) }.to raise_error(
          ArgumentError, /Invalid --publication-date-after.*out of range/
        )
      end

      it "rejects date-after >= date-before" do
        command = ["fetch", "--publication-date-after", "2010",
                   "--publication-date-before", "2008", "ISO 2146"]
        expect { Relaton::Cli.start(command) }.to raise_error(
          ArgumentError, /Invalid date range/
        )
      end
    end

    context do
      let(:io) { double "IO" }

      # Building the ISO index (decompress + parse ~79k entries) costs ~25s and
      # is the dominant cost of these examples. Build the DB once and reuse the
      # in-memory index across the examples below: the first fetch builds it,
      # the rest reuse it (warm fetch is ~0.04s).
      before(:context) do
        @tmpdir = Dir.mktmpdir("relaton_test_cache")
        # Isolate from global cache by using a fresh DB in a temp directory
        Relaton::Cli::RelatonDb.instance.instance_variable_set(:@db, nil)
        Relaton::Cli.relaton(@tmpdir)
      end

      after(:context) do
        Relaton::Cli::RelatonDb.instance.instance_variable_set(:@db, nil)
        FileUtils.remove_entry(@tmpdir)
      end

      before(:each) do
        RSpec::Mocks.space.proxy_for(IO).reset
        expect(IO).to receive(:new) do |arg1, arg2, &block|
          if arg1.is_a?(Integer) then io
          else block.call(arg1, arg2)
          end
        end.at_most(2).times

        # Force to download index file (only takes effect on the first fetch,
        # which builds the shared index; warm fetches never hit this path)
        require "relaton/index"
        allow_any_instance_of(Relaton::Index::Type).to receive(:actual?).and_return(false)
        allow_any_instance_of(Relaton::Index::FileIO).to receive(:check_file).and_return(nil)
      end

      it "calls fetch and return XML" do
        expect(io).to receive(:puts) do |arg|
          expect(arg).to match(/^<bibdata type="standard" schema-version="v\d\.\d\.\d">/)
          expect(arg).to include '<docidentifier type="ISO" primary="true">'\
                                 "ISO 2146:2010</docidentifier>"
          expect(arg).to include '<relation type="obsoletes">'
        end
        VCR.use_cassette "iso_2146" do
          command = ["fetch", "--type", "iso", "ISO 2146"]
          Relaton::Cli.start(command)
        end
      end

      it "calls fetch and return YAML" do
        expect(io).to receive(:puts) do |arg|
          expect(arg).to include "- content: ISO 2146:2010"
        end
        VCR.use_cassette "iso_2146" do
          command = ["fetch", "--type", "iso", "--format", "yaml", "ISO 2146"]
          Relaton::Cli.start(command)
        end
      end

      it "calls fetch and return BibTex" do
        expect(io).to receive(:puts) do |arg|
          expect(arg).to include "@misc{ISO2146,"
        end
        VCR.use_cassette "iso_2146" do
          command = ["fetch", "--type", "iso", "--format", "bibtex", "ISO 2146"]
          Relaton::Cli.start(command)
        end
      end
    end

    # CLI-layer behaviour (option forwarding, output for a missing match) is
    # exercised against a mocked DB. The happy-path index integration is
    # already covered end-to-end by the VCR specs above; going through the real
    # ISO index here would re-sort ~79k entries per example for no added
    # coverage. (These replace former specs that shelled out to a globally
    # installed `relaton` over live network.)
    context "with a mocked DB" do
      let(:db) { double "DB" }
      let(:io) { double "IO" }

      before do
        expect(Relaton::Cli).to receive(:relaton).and_return(db)
      end

      it "forwards the year option to the processor" do
        expect(db).to receive(:fetch_std)
          .with("ISO 2146", "2010", :relaton_iso, type: "ISO", year: 2010)
        Relaton::Cli.start ["fetch", "--type", "ISO", "--year", "2010", "ISO 2146"]
      end

      it "warns when the year does not match" do
        expect(db).to receive(:fetch_std).and_return(nil)
        expect(io).to receive(:puts).with("No matching bibliographic entry found")
        expect(IO).to receive(:new).with(kind_of(Integer), mode: "w:UTF-8").and_return io
        Relaton::Cli.start ["fetch", "--type", "ISO", "--year", "2009", "ISO 2146"]
      end

      it "warns when the standard is undefined" do
        expect(db).to receive(:fetch_std).and_return(nil)
        expect(io).to receive(:puts).with("No matching bibliographic entry found")
        expect(IO).to receive(:new).with(kind_of(Integer), mode: "w:UTF-8").and_return io
        Relaton::Cli.start ["fetch", "--type", "ISO", "ISO 123456"]
      end
    end

    context "fetch code with invalid/missing type" do
      it "calls supported_type_message method" do
        io = double "IO"
        expect(io).to receive(:puts).with(
          "Recognised types: 3GPP, BIPM, BSI, CC, CCSDS, CEN, CIE, CN, DOI, " \
          "ECMA, ETSI, IANA, IEC, IEEE, IETF, IHO, ISBN, ISO, ITU, JIS, NIST, OASIS, " \
          "OGC, OMG, PLATEAU, UN, W3C, XEP"
        )
        expect(IO).to receive(:new).with(kind_of(Integer), mode: "w:UTF-8").and_return io
        Relaton::Cli.start ["fetch", "ISO 2146", "--type", "invalid"]
      end

      # it "prints a warning message for missing --type option" do
      #   _, stderr, = Open3.capture3("relaton fetch 'ISO 2146'")
      #   expect(stderr).to include("required options '--type'")
      # end
    end

    it "raise request error" do
      expect(db).to receive(:fetch_std).and_raise Relaton::RequestError
      expect(Relaton::Cli).to receive(:relaton).and_return(db)
      command = Relaton::Cli::Command.new
      # expect(command).to receive(:registered_types).and_return ["ISO"]
      expect(command.send(:fetch_document, "ISO 2146", type: "ISO")).to eq(
        "Relaton::RequestError",
      )
      Relaton::Cli::RelatonDb.instance.instance_variable_set :@db, nil
    end
  end
end
