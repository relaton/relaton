RSpec.describe Relaton::Cli::SubcommandCollection do
  let(:dir) { "spec/fixtures" }

  # The collections live in a lutaml-store store under `<dir>/v2` (#549).
  def stored(name, directory = dir)
    Relaton::Cli::CollectionStore.new(directory).get(name)
  end

  def stored_ids(name, directory = dir)
    # An imported collection nests in the collection it is imported into.
    stored(name, directory).items_flattened.flatten
      .map { |i| i.docidentifier.to_s }
  end

  # A fetched document: a hash item, as `Bibcollection#<<` takes it.
  let(:doc) do
    { "id" => "CCDIR10005", "docidentifier" =>
      [{ "type" => "CC", "content" => "CC/DIR 10005", "primary" => true }] }
  end

  context "create collection" do
    it do
      file = "collection.yaml"
      tmp = "tmp"
      Relaton::Cli::Command.start(
        [
          "collection", "create", file, "-d", tmp, "--title", "Title",
          "--author", "Author", "--doctype", "ISO"
        ],
      )
      coll = stored file, tmp
      expect(coll.title).to eq "Title"
      expect(coll.author).to eq "Author"
      expect(coll.doctype).to eq "ISO"
      expect(File.exist?(File.join(tmp, file))).to be false
    end

    it "out error mesage" do
      file = "sample-collection.yaml"
      expect do
        Relaton::Cli::Command.start ["collection", "create", file, "-d", dir]
      end.to output(/Collection `#{file}` aready exist/).to_stderr_from_any_process
    end
  end

  it "show info" do
    out = %r{
      Collection:\s.*?\n
      Last\supdated:\s\d{4}-\d{2}-\d{2}.*?\n
      File\ssize:\s\d+\n
      Number\sof\sitems:\s\d+\n
      Author:\s.*?\n
      Title:\s\w+
    }x
    expect do
      Relaton::Cli::Command.start(
        ["collection", "info", "sample-collection.yaml", "-d", dir],
      )
    end.to output(out).to_stdout
  end

  %w[info export].each do |command|
    it "#{command} warns about a missing collection" do
      expect do
        Relaton::Cli::Command.start ["collection", command, "none.yaml", "-d", dir]
      end.to output(/Collection `none.yaml` does not exist/)
        .to_stderr_from_any_process
    end
  end

  context "list" do
    it "collections" do
      expect do
        Relaton::Cli::Command.start(
          ["collection", "ls", "-d", dir],
        )
      end.to output("sample-collection.yaml\n").to_stdout
    end

    it "entries" do
      expect do
        Relaton::Cli::Command.start(
          ["collection", "ls", "-e", "-d", dir],
        )
      end.to output(/CC 36000/).to_stdout
    end
  end

  context "get document by docid" do
    shared_examples "get" do |collection, format|
      it do
        args = ["collection", "get", "CC 34005", "-d", dir]
        args += ["-c", collection] if collection
        args += ["-f", format] if format
        expect { Relaton::Cli::Command.start args }.to output(out_regex)
          .to_stdout
      end
    end

    context do
      let(:out_regex) { /Document identifier: CC 34005/ }

      context "from specified collection" do
        include_examples "get", "sample-collection.yaml"
      end

      context("across all collections") { include_examples "get" }
    end

    context "and output it in" do
      context "Asciibib format" do
        let(:out_regex) { /id:: CC34005/ }
        include_examples "get", nil, "abb"
      end

      context "XML format" do
        let(:out_regex) { /<docidentifier type="CC" primary="true">CC 34005/ }
        include_examples "get", nil, "xml"
      end
    end

    context "and write it to" do
      it "Asciibib file" do
        file = "tmp/cc_34005.abb"
        expect(File).to receive(:write).with file, /id:: CC34005/, kind_of(Hash)
        Relaton::Cli::Command.start(
          ["collection", "get", "CC 34005", "-d", dir, "-o", file],
        )
      end

      it "XML file" do
        file = "tmp/cc_34005.xml"
        expect(File).to receive(:write).with(
          file, /<docidentifier type="CC" primary="true">CC 34005/, kind_of(Hash)
        )
        Relaton::Cli::Command.start(
          ["collection", "get", "CC 34005", "-d", dir, "-o", file],
        )
      end
    end
  end

  context "search text in" do
    shared_examples "search" do |text, regex|
      it "of collection" do
        expect do
          Relaton::Cli::Command.start ["collection", "search", text, "-d", dir]
        end.to output(regex).to_stdout
      end
    end

    context "document identifiers" do
      include_examples "search", "34006", /CC\/S \e\[4m34006\e\[24m/
    end

    context "in titles" do
      include_examples(
        "search", "Calendars",
        /Date and time -- \e\[4mCalendars\e\[24m -- Gregorian calend\.{3}/
      )
    end
  end

  context "fetch document" do
    let(:coll) { "sample-collection.yaml" }

    it "and store into collection" do
      db = double "db"
      expect(Relaton).to receive(:db).and_return db
      expect(db).to receive(:fetch).with("CC/DIR 10005", nil).and_return doc

      Relaton::Cli::Command.start [
        "collection", "fetch", "CC/DIR 10005", "-t", "CC", "-d", dir,
        "-c", coll
      ]
      expect(stored_ids(coll)).to include "CC 36000", "CC/DIR 10005"
    end

    it "and store the item class Db#fetch returns" do
      item = Relaton::Bib::Item.from_xml File.read("spec/fixtures/bib_item.xml")
      db = double "db"
      expect(Relaton).to receive(:db).and_return db
      expect(db).to receive(:fetch).and_return item

      Relaton::Cli::Command.start [
        "collection", "fetch", "ISO 55000", "-t", "ISO", "-d", dir, "-c", coll
      ]
      expect(stored_ids(coll)).to include "ISO 55000:2014"
      expect(stored(coll).items.last.title.first.content)
        .to eq "Geographic information"
    end

    it "and create the collection when it is missing" do
      db = double "db"
      expect(Relaton).to receive(:db).and_return db
      expect(db).to receive(:fetch).and_return doc

      Relaton::Cli::Command.start [
        "collection", "fetch", "CC/DIR 10005", "-t", "CC", "-d", dir,
        "-c", "new.yaml"
      ]
      expect(stored_ids("new.yaml")).to eq ["CC/DIR 10005"]
    end

    context "with publication date options" do

      it "forwards parsed Date for --publication-date-before" do
        db = double "db"
        expect(Relaton).to receive(:db).and_return db
        expect(db).to receive(:fetch).with(
          "CC/DIR 10005", nil,
          publication_date_before: Date.new(2020, 6, 1),
        ).and_return doc

        Relaton::Cli::Command.start [
          "collection", "fetch", "CC/DIR 10005", "-t", "CC", "-d", dir,
          "-c", coll, "--publication-date-before", "2020-06"
        ]
        expect(stored_ids(coll)).to include "CC/DIR 10005"
      end

      it "forwards parsed Date for --publication-date-after" do
        db = double "db"
        expect(Relaton).to receive(:db).and_return db
        expect(db).to receive(:fetch).with(
          "CC/DIR 10005", nil,
          publication_date_after: Date.new(2019, 1, 1),
        ).and_return doc

        Relaton::Cli::Command.start [
          "collection", "fetch", "CC/DIR 10005", "-t", "CC", "-d", dir,
          "-c", coll, "--publication-date-after", "2019"
        ]
        expect(stored_ids(coll)).to include "CC/DIR 10005"
      end

      it "forwards both date options as parsed Dates" do
        db = double "db"
        expect(Relaton).to receive(:db).and_return db
        expect(db).to receive(:fetch).with(
          "CC/DIR 10005", nil,
          publication_date_after: Date.new(2019, 1, 1),
          publication_date_before: Date.new(2020, 6, 15),
        ).and_return doc

        Relaton::Cli::Command.start [
          "collection", "fetch", "CC/DIR 10005", "-t", "CC", "-d", dir,
          "-c", coll, "--publication-date-after", "2019",
          "--publication-date-before", "2020-06-15"
        ]
        expect(stored_ids(coll)).to include "CC/DIR 10005"
      end

      it "raises ArgumentError for invalid date format" do
        expect {
          Relaton::Cli::Command.start [
            "collection", "fetch", "CC/DIR 10005", "-t", "CC", "-d", dir,
            "-c", coll, "--publication-date-before", "not-a-date"
          ]
        }.to raise_error(ArgumentError, /Invalid --publication-date-before/)
      end

      it "raises ArgumentError when after date is not before the before date" do
        expect {
          Relaton::Cli::Command.start [
            "collection", "fetch", "CC/DIR 10005", "-t", "CC", "-d", dir,
            "-c", coll, "--publication-date-after", "2020",
            "--publication-date-before", "2019"
          ]
        }.to raise_error(ArgumentError, /Invalid date range/)
      end
    end

    it "reports a friendly message for a malformed identifier" do
      db = double "db"
      expect(Relaton).to receive(:db).and_return db
      expect(db).to receive(:fetch)
        .and_raise Pubid::Errors::ParseError.new("bad id")
      expect do
        Relaton::Cli::Command.start [
          "collection", "fetch", "not a reference", "-t", "ISO",
          "-d", "spec/fixtures", "-c", "sample-collection.yaml"
        ]
      end.to output(/"not a reference" is not a recognized standards identifier/)
        .to_stderr_from_any_process
    end

    it "logs a reference no flavor recognizes" do
      db = double "db"
      expect(Relaton).to receive(:db).and_return db
      expect(db).to receive(:fetch)
        .and_raise Relaton::UnknownReferenceError.new("XYZ 1")
      expect do
        Relaton::Cli::Command.start [
          "collection", "fetch", "XYZ 1", "-t", "ISO",
          "-d", "spec/fixtures", "-c", "sample-collection.yaml"
        ]
      end.to output(/`XYZ 1` is not a recognized standards identifier/)
        .to_stderr_from_any_process
    end

    it "logs a reference the offline local store lacks" do
      db = double "db"
      expect(Relaton).to receive(:db).and_return db
      expect(db).to receive(:fetch)
        .and_raise Relaton::NotInLocalStoreError.new("ISO 2146", ["/c"])
      before = stored_ids "sample-collection.yaml"
      expect do
        Relaton::Cli::Command.start [
          "collection", "fetch", "ISO 2146", "-t", "ISO",
          "-d", "spec/fixtures", "-c", "sample-collection.yaml"
        ]
      end.to output(/`ISO 2146` is not in the local store/)
        .to_stderr_from_any_process
      expect(stored_ids("sample-collection.yaml")).to eq before
    end

    it "logs a transport failure" do
      db = double "db"
      expect(Relaton).to receive(:db).and_return db
      expect(db).to receive(:fetch)
        .and_raise Relaton::RequestError, "Could not access https://example"
      before = stored_ids "sample-collection.yaml"
      expect do
        Relaton::Cli::Command.start [
          "collection", "fetch", "ISO 2146", "-t", "ISO",
          "-d", "spec/fixtures", "-c", "sample-collection.yaml"
        ]
      end.to output(/Could not access https:\/\/example/)
        .to_stderr_from_any_process
      expect(stored_ids("sample-collection.yaml")).to eq before
    end

    it "reports a friendly message for an identifier pubid cannot take" do
      db = double "db"
      expect(Relaton).to receive(:db).and_return db
      expect(db).to receive(:fetch)
        .and_raise Pubid::Errors::InvalidInputError.new("too long")
      expect do
        Relaton::Cli::Command.start [
          "collection", "fetch", "not a reference", "-t", "ISO",
          "-d", "spec/fixtures", "-c", "sample-collection.yaml"
        ]
      end.to output(/"not a reference" is not a recognized standards identifier/)
        .to_stderr_from_any_process
    end
  end

  it "export collection" do
    dir = "spec/fixtures"
    file = "sample-collection.yaml"
    outfile = "#{file.sub(/\.\w+$/, '')}.xml"
    expect(File).to receive(:write).with(
      outfile, /<docidentifier type="CC" primary="true">CC\s36000<\/docidentifier>/,
      kind_of(Hash)
    )
    Relaton::Cli::Command.start ["collection", "export", file, "-d", dir]
  end

  context "import" do
    after(:example) { expect(stored_ids(coll)).to include "CC 18001" }

    shared_examples "import" do |source|
      it "XML" do
        Relaton::Cli::Command.start [
          "collection", "import", source, "-c", coll, "-d", dir
        ]
      end
    end

    context "into existed collection" do
      let(:coll) { "sample-collection.yaml" }

      include_examples "import", "spec/fixtures/sample.rxl"
      include_examples "import", "spec/fixtures/sample-coll.xml"
    end

    context "into new collection" do
      let(:coll) { "no-exist-collection.yaml" }

      include_examples "import", "spec/fixtures/sample.rxl"
      include_examples "import", "spec/fixtures/sample-coll.xml"
    end
  end
end
