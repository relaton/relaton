require "fileutils"
require "open3"

RSpec.describe Relaton::Cli::RelatonFile do
  describe ".extract" do
    before { FileUtils.mkdir_p("./tmp/output") }
    after { FileUtils.rm_rf("./tmp/output") }

    context "with Metanorma XML" do
      it "extracts Metanorma XML in the output directory" do
        Relaton::Cli::RelatonFile.extract(
          "spec/assets/metanorma-xml", "./tmp/output"
        )

        content = File.read("./tmp/output/a.rxl")

        expect(file_exist?("cc-amd-86003.rxl")).to be false
        expect(file_exist?("cc-cor-12990-3.rxl")).to be true
        expect(content).to match(/<bibdata type="standard" schema-version="v[\d.]+">/)
      end
    end

    context "with Metanorma XML and different extension" do
      it "extracts XML in output directory with provided extension" do
        Relaton::Cli::RelatonFile.extract(
          "spec/assets/metanorma-xml",
          "./tmp/output", extension: "rxml"
        )

        expect(file_exist?("a.rxl")).to be false
        expect(file_exist?("a.rxml")).to be true
        expect(file_exist?("cc-cor-12990-3.rxl")).to be false
        expect(file_exist?("cc-cor-12990-3.rxml")).to be true
      end
    end

    context "with single Metanorma XML file" do
      it "extracts the XML in the output directory" do
        Relaton::Cli::RelatonFile.extract(
          "spec/assets/metanorma-xml/a.xml",
          "./tmp/output", extension: "rxl"
        )

        content = File.read("./tmp/output/a.rxl")

        expect(file_exist?("a.rxl")).to be_truthy
        expect(file_exist?("cc-cor-12990-3.rxl")).to be_falsey
        expect(content).to match(/<bibdata type="standard" schema-version="v[\d.]+">/)
      end

      it "extracts the RFC in the output directory" do
        Relaton::Cli::RelatonFile.extract(
          "spec/fixtures/draft-celi-acvp-sha-00.xml",
          "./tmp/output", extension: "rxl"
        )

        content = File.read("./tmp/output/draft-celi-acvp-sha-00.rxl")

        expect(file_exist?("draft-celi-acvp-sha-00.rxl")).to be_truthy
        expect(file_exist?("cc-cor-12990-3.rxl")).to be_falsey
        expect(content).to match(/<bibdata type="standard" schema-version="v[\d.]+">/)
      end

      it "extract to current directory" do
        Relaton::Cli::RelatonFile.extract(
          "spec/fixtures/antioch.xml", "./tmp/output", extension: "rxl"
        )
        expect(File.read("./tmp/output/antioch.rxl")).to include(
          "<docnumber>draft-camelot-holy-grenade-01</docnumber>",
        )
      end
    end
  end

  describe "reading the input (relaton#580)" do
    let(:bibdata_body) do
      '<title>Namespaced</title><docidentifier primary="true">CC 99001</docidentifier>'
    end

    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        example.run
      end
    end

    def write_input(name, content)
      File.join(@dir, name).tap { |path| File.write(path, content) }
    end

    it "does not parse with Nokogiri" do
      source = File.read(File.expand_path(
        "../../../../lib/relaton/cli/relaton_file.rb", __dir__
      ))
      expect(source).not_to include "Nokogiri"
      expect(source).not_to include "nokogiri"
    end

    it "extracts a bibdata from a document in a default namespace" do
      file = write_input "ns.xml", <<~XML
        <standard xmlns="https://www.metanorma.org/ns/standoc">
          <bibdata type="standard">#{bibdata_body}</bibdata>
          <sections/>
        </standard>
      XML
      out = File.join(@dir, "out")
      FileUtils.mkdir_p out
      Relaton::Cli::RelatonFile.extract(file, out, extension: "rxl")

      content = File.read(File.join(out, "ns.rxl"))
      expect(content).to include "<docidentifier primary=\"true\">CC 99001</docidentifier>"
      expect(content).to include "<title>Namespaced</title>"
    end

    it "extracts a bibdata from a document in a prefixed namespace" do
      file = write_input "prefixed.xml", <<~XML
        <m:standard xmlns:m="https://www.metanorma.org/ns/standoc">
          <m:bibdata type="standard"><m:title>Namespaced</m:title><m:docidentifier primary="true">CC 99001</m:docidentifier></m:bibdata>
        </m:standard>
      XML
      out = File.join(@dir, "out")
      FileUtils.mkdir_p out
      Relaton::Cli::RelatonFile.extract(file, out, extension: "rxl")

      content = File.read(File.join(out, "prefixed.rxl"))
      expect(content).to include "<docidentifier primary=\"true\">CC 99001</docidentifier>"
    end

    it "extracts a bibdata from a namespace-free document" do
      file = write_input "plain.xml",
                         "<standard><bibdata type=\"standard\">#{bibdata_body}</bibdata></standard>"
      out = File.join(@dir, "out")
      FileUtils.mkdir_p out
      Relaton::Cli::RelatonFile.extract(file, out, extension: "rxl")

      expect(File.read(File.join(out, "plain.rxl"))).to include "CC 99001"
    end

    it "extracts through bin/relaton, with only the CLI loaded" do
      # In process, the suite has loaded Nokogiri already; a fresh process
      # shows whether Cli.parse_xml finds it.
      file = write_input "cli.xml",
                         "<standard><bibdata type=\"standard\">#{bibdata_body}</bibdata></standard>"
      out = File.join(@dir, "out")
      FileUtils.mkdir_p out
      bin = File.expand_path("../../../../bin/relaton", __dir__)
      _, err, status = Open3.capture3(RbConfig.ruby, bin, "extract", file, out)

      expect(status).to be_success, err
      expect(File.read(File.join(out, "cli.rxl"))).to include "CC 99001"
    end

    it "warns and skips a file that is not well-formed" do
      write_input "bad.rxl", "<bibdata>#{bibdata_body}<p></bibdata>"
      write_input "good.rxl", "<bibdata>#{bibdata_body}</bibdata>"
      outfile = File.join(@dir, "out.yml")

      expect do
        Relaton::Cli::RelatonFile.concatenate(@dir, outfile, extension: "yml")
      end.to output(/Skipping .*bad\.rxl: not well-formed XML/).to_stderr_from_any_process

      expect(YAML.load_file(outfile)["root"]["items"].size).to eq 1
    end

    it "concatenates a namespaced bibdata and skips an empty file" do
      write_input "a.rxl",
                  "<bibdata xmlns=\"https://open.ribose.com/relaton-xml\" type=\"standard\">" \
                  "#{bibdata_body}</bibdata>"
      write_input "b.rxl", ""
      write_input "c.xml", "<other><bibdata>#{bibdata_body}</bibdata></other>"
      outfile = File.join(@dir, "out.yml")
      Relaton::Cli::RelatonFile.concatenate(@dir, outfile, extension: "yml")

      items = YAML.load_file(outfile)["root"]["items"]
      expect(items.size).to eq 1
      expect(items[0]["docidentifier"][0]["content"]).to eq "CC 99001"
      expect(items[0]["source"].detect { |l| l["type"] == "rxl" }["content"])
        .to eq File.join(@dir, "a.rxl")
    end
  end

  describe ".concatenate" do
    context "with YAML & RXL files in source directory" do
      it "combines both type of files into a collection" do
        Relaton::Cli::RelatonFile.concatenate(
          "spec/fixtures", "./tmp/concatenate.yml", extension: "yml"
        )

        hashdoc = YAML.load_file("./tmp/concatenate.yml")

        expect(hashdoc["root"]["title"]).to be_nil
        expect(hashdoc["root"]["author"]).to be_nil

        items = hashdoc["root"]["items"]
        #warn items
        expect(items[0]["docidentifier"][0]["content"]).to eq("CC 18001")
        expect(items[1]["docidentifier"][0]["content"]).to eq("CC 36000")
        expect(items[2]["xml"]).not_to eq("spec/fixtures/sample-collection")
      end
    end

    context "with YAML, RXL files and custom options" do
      it "combines both type of files and usages the options" do
        Relaton::Cli::RelatonFile.concatenate(
          "spec/fixtures", "./tmp/concatenate.yml",
          title: "collection title", organization: "Ribose Inc",
          extension: "yml"
        )

        hashdoc = YAML.load_file("./tmp/concatenate.yml")

        expect(hashdoc["root"]["title"]).to eq("collection title")
        expect(hashdoc["root"]["author"]).to eq("Ribose Inc")
        expect(hashdoc["root"]["items"][1]["docidentifier"][0]["content"]).to eq("CC 36000")
      end

      it "uses the new Relaton XML format" do
        Relaton::Cli::RelatonFile.concatenate(
          "spec/fixtures", "./tmp/concatenate.yml",
          title: "collection title", organization: "Ribose Inc",
          extension: "yml"
        )

        hashdoc = YAML.load_file("./tmp/concatenate.yml")
        items = hashdoc["root"]["items"].sort_by { |item| item["id"].to_s }

        expect(hashdoc["root"]["title"]).to eq("collection title")
        expect(hashdoc["root"]["author"]).to eq("Ribose Inc")
        expect(items[3]["docidentifier"][0]["content"]).to eq("CC 36000")
        expect(items[3]["docidentifier"][0]["type"]).to eq("CC")
      end

      it "with IETF sample files" do
        file = "spec/fixtures/ietf_index.rxl"
        Relaton::Cli::RelatonFile.concatenate(
          "spec/fixtures/documents", file,
          title: "Collection title", organization: "Ribose",
          extension: "rxl"
        )

        content = File.read file, encoding: "UTF-8"
        expect(content).to include "<docidentifier primary=\"true\">1149</docidentifier>"
        expect(content).to include '<uri type="rxl">spec/fixtures/documents/example.rxl</uri>'
        expect(content).to include "<docidentifier primary=\"true\">draft-camelot-holy-grenade-01</docidentifier>"
        expect(content).to include '<uri type="rxl">spec/fixtures/documents/antioch.rxl</uri>'
      end
    end

    context "with YAML, RXL and linked documents" do
      let(:file_types) { ["xml", "pdf", "doc", "html"] }

      before { create_fixture_files("sample", file_types) }
      after { cleanup_fixture_files("sample", file_types) }

      it "combines documents and also add dynamic links" do
        Relaton::Cli::RelatonFile.concatenate(
          "spec/fixtures", "./tmp/concatenate.yml", extension: "yml"
        )

        hashdoc = YAML.load_file("./tmp/concatenate.yml")
        items = hashdoc["root"]["items"]

        expect(hashdoc["root"]["title"]).to be_nil
        expect(hashdoc["root"]["author"]).to be_nil

        expect(items[0]["docidentifier"][0]["content"]).to eq("CC 18001")
        expect(items[0]["source"].detect { |l| l["type"] == "xml" }["content"]).to eq("spec/fixtures/sample.xml")
        expect(items[0]["source"].detect { |l| l["type"] == "pdf" }["content"]).to eq("spec/fixtures/sample.pdf")
        expect(items[0]["source"].detect { |l| l["type"] == "doc" }["content"]).to eq("spec/fixtures/sample.doc")
        expect(items[0]["source"].detect { |l| l["type"] == "html" }["content"]).to eq("spec/fixtures/sample.html")
      end
    end
  end

  describe "split" do
    before { FileUtils.mkdir_p("./tmp/output") }
    after { FileUtils.rm_rf("./tmp/output") }

    context "with valid collection and output dir" do
      it "split the relaton collection into multiple files in XML format" do
        output_dir = "./tmp/output"
        collection_file = "spec/fixtures/sample-collection.xml"

        Relaton::Cli::RelatonFile.split(collection_file, output_dir, extension: "rxl")
        content = File.read([output_dir, "cc-34000.rxl"].join("/"))

        expect(file_exist?("cc-34000.rxl")).to be true
        expect(Dir["#{output_dir}/**"].length).to eq(6)
        expect(content).to match(/<bibdata type="standard" schema-version="v[\d.]+">/)
        expect(content).to include("<title>Date and time -- Concepts")
      end

      it "split the relaton collection into multiple files in YAML format" do
        output_dir = "./tmp/output"
        collection_file = "spec/fixtures/sample-collection.xml"

        Relaton::Cli::RelatonFile.split(collection_file, output_dir, new: true, extension: "yaml")
        content = File.read([output_dir, "cc-34000.yaml"].join("/"))

        expect(file_exist?("cc-34000.yaml")).to be true
        expect(Dir["#{output_dir}/**"].length).to eq(6)
        expect(content).to include("id: CC34000")
        expect(content).to include("title:\n- content: Date and time -- Concepts and vocabulary")
      end

      it "split the relaton collection into default dir" do
        output_dir = "./sample-collection"
        collection_file = "spec/fixtures/sample-collection.xml"

        Relaton::Cli::RelatonFile.split(collection_file, nil, new: true, extension: "yaml")
        content = File.read([output_dir, "cc-34000.yaml"].join("/"))

        expect(File.exist?("#{output_dir}/cc-34000.yaml")).to be true
        expect(Dir["#{output_dir}/**"].length).to eq(6)
        expect(content).to include("id: CC34000")
        expect(content).to include("title:\n- content: Date and time -- Concepts and vocabulary")
        FileUtils.rm_rf output_dir
      end
    end
  end

  def file_exist?(file, directory = "./tmp/output")
    File.exist?([directory, file].join("/"))
  end

  def cleanup_fixture_files(name, types = [])
    types.each { |type| FileUtils.rm_f("spec/fixtures/#{name}.#{type}") }
  end

  def create_fixture_files(name, types = [])
    types.each do |type|
      FileUtils.cp("spec/fixtures/sample.rxl", "spec/fixtures/#{name}.#{type}")
    end
  end
end
