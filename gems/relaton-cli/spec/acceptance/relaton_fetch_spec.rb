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

    # These exercise the full Relaton::Db fetch path (registry → cache →
    # check_bibliocache → serialization) for each output format. The only thing
    # stubbed is the external flavor boundary Relaton::Iso::Bibliography.get,
    # which is where the ~79k-entry index build and HTTP document fetch happen;
    # stubbing it to return a fixture-parsed item keeps the real DB and real
    # serialization in the path while dropping ~25s of index work and the
    # network round-trip (replaces a slow, index-version-fragile VCR cassette).
    context "fetch output serialization" do
      let(:io) { double "IO" }
      let(:doc) do
        require "relaton/iso"
        Relaton::Iso::Item.from_yaml(File.read("spec/acceptance/fixtures/iso_2146.yaml"))
      end

      around do |example|
        Dir.mktmpdir("relaton_test_cache") do |dir|
          # Isolate from the global cache by using a fresh DB in a temp directory
          Relaton::Cli::RelatonDb.instance.instance_variable_set(:@db, nil)
          Relaton::Cli.relaton(dir)
          example.run
          Relaton::Cli::RelatonDb.instance.instance_variable_set(:@db, nil)
        end
      end

      before do
        allow(Relaton::Iso::Bibliography).to receive(:get).and_return(doc)
        # IO.new is stubbed because Command#fetch calls $stdout.fcntl, which is
        # unimplemented on a StringIO; the double captures the serialized output.
        expect(IO).to receive(:new)
          .with(kind_of(Integer), mode: "w:UTF-8").and_return io
      end

      it "calls fetch and return XML" do
        expect(io).to receive(:puts) do |arg|
          expect(arg).to match(/^<bibdata type="standard" schema-version="v\d\.\d\.\d">/)
          expect(arg).to include '<docidentifier type="ISO" primary="true">'\
                                 "ISO 2146:2010</docidentifier>"
          expect(arg).to include '<relation type="obsoletes">'
        end
        Relaton::Cli.start ["fetch", "--type", "iso", "ISO 2146"]
      end

      it "calls fetch and return YAML" do
        expect(io).to receive(:puts) do |arg|
          expect(arg).to include "- content: ISO 2146:2010"
        end
        Relaton::Cli.start ["fetch", "--type", "iso", "--format", "yaml", "ISO 2146"]
      end

      it "calls fetch and return BibTex" do
        expect(io).to receive(:puts) do |arg|
          expect(arg).to include "@misc{ISO21462010,"
        end
        Relaton::Cli.start ["fetch", "--type", "iso", "--format", "bibtex", "ISO 2146"]
      end
    end

    # CLI-layer behaviour (option forwarding, output for a missing match) is
    # exercised against a mocked DB. Serialization of a fetched item is already
    # covered by the "fetch output serialization" specs above; going through the
    # real ISO index here would re-sort ~79k entries per example for no added
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
          "OGC, OIML, OMG, PLATEAU, UN, W3C, XEP"
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
