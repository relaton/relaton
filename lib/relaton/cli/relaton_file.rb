require "moxml"
require "pathname"

module Relaton
  module Cli
    class RelatonFile
      def initialize(source, options = {})
        @source = source
        @options = options
        @outdir = options.fetch(:outdir, nil)
        @outfile = options.fetch(:outfile, nil)
      end

      def extract
        extract_and_write_to_files
      end

      def concatenate
        concatenate_and_write_to_files
      end

      def split
        split_and_write_to_files
      end

      # Extract files
      #
      # This interface expect us to provide a source file / directory,
      # output directory and custom configuration options. Then it wll
      # extract Relaton XML file / files to output directory from the
      # source file / directory. During this process it will use custom
      # options when available.
      #
      # @param source [Dir] The source directory for files
      # @param outdir [Dir] The output directory for files
      # @param options [Hash] Options as hash key value pair
      #
      def self.extract(source, outdir, options = {})
        new(source, options.merge(outdir: outdir)).extract
      end

      # Concatenate files
      #
      # This interface expect us to provide a source directory, output
      # file and custom configuration options. Normally, this expect the
      # source directory to contain RXL fles, but it also converts any
      # YAML files to RXL and then finally combines those together.
      #
      # This interface also allow us to provdie options like title and
      # organization and then it usage those details to generate the
      # collection file.
      #
      # @param source [Dir] The source directory for files
      # @param output [String] The collection output file
      # @param options [Hash] Options as hash key value pair
      #
      def self.concatenate(source, outfile, options = {})
        new(source, options.merge(outfile: outfile)).concatenate
      end

      # Split collection
      #
      # This interface expects us to provide a Relaton Collection
      # file and also an output directory, then it will split that
      # collection into multiple files.
      #
      # By default it usages `rxl` extension for these new files,
      # but we can also customize that by providing the correct
      # one as `extension` option parameter.
      #
      # @param source [File] The source collection file
      # @param output [Dir] The output directory for files
      # @param options [Hash] Options as hash key value pair
      #
      def self.split(source, outdir = nil, options = {})
        new(source, options.merge(outdir: outdir)).split
      end

      private

      attr_reader :source, :options, :outdir, :outfile

      def bibcollection
        Bibcollection.new(
          title: options[:title],
          items: concatenate_files,
          doctype: options[:doctype],
          author: options[:organization],
        )
      end

      def select_source_files
        if File.file?(source)
          [source]
        else
          select_files_with("xml")
        end
      end

      def relaton_collection
        @relaton_collection ||=
          Bibcollection.from_xml(File.read(source, encoding: "utf-8"))
      end

      def extract_and_write_to_files
        select_source_files.each do |file|
          xml = extract_bibdata_xml(File.read(file, encoding: "utf-8"), file)
          bibdata = xml && Relaton::Bibdata.from_xml(xml)
          next unless bibdata

          build_bibdata_relaton(bibdata, file)
          write_to_file(bibdata.send(output_type), outdir, build_filename(file))
        end
      end

      # The bibdata XML of the first `bibdata` element, or of the first `rfc`
      # element, in any namespace.
      #
      # @param content [String] XML
      # @param file [String] path to file
      # @return [String, nil]
      def extract_bibdata_xml(content, file)
        doc = parse_xml_document(content, file)
        return unless doc

        if (bib = find_element(doc, "bibdata"))
          element_xml(bib)
        elsif (rfc = find_element(doc, "rfc"))
          rfc_bibdata_xml(element_xml(rfc))
        end
      end

      # Map all relevant files to the corresponding bibdata instances
      #
      # @return [Array<Relaton::Bibdata>]
      def concatenate_files
        xml_files = [convert_rxl_to_xml, convert_yamls_to_xml,
                     convert_xml_to_xml]

        xml_files.flatten.reduce([]) do |mem, xml|
          bib = concatenate_bibdata_xml(xml[:content], xml[:file])
          bib ? mem << bibdata_instance(bib, xml[:file]) : mem
        end
      end

      # The bibdata XML of a document whose root is `rfc`, `bibitem` or
      # `bibdata`, in any namespace.
      #
      # @param content [String] XML
      # @param file [String] path to file
      # @return [String, nil]
      def concatenate_bibdata_xml(content, file)
        root = parse_xml_document(content, file)&.root
        case root&.name
        when "rfc" then rfc_bibdata_xml(element_xml(root))
        when "bibitem", "bibdata" then element_xml(root)
        end
      end

      # Moxml does not recover a malformed document: warn
      # and skip the file. An empty file is skipped without a warning.
      #
      # @param content [String] XML
      # @param file [String] path to file
      # @return [Moxml::Document, nil] nil when the content is not XML
      def parse_xml_document(content, file)
        Moxml.new.parse(content)
      rescue Moxml::ParseError => e
        unless content.to_s.strip.empty?
          Util.warn "Skipping #{file}: not well-formed XML " \
                    "(#{e.message.lines.first&.strip})"
        end
        nil
      end

      # The root element when it has the name, else the first descendant
      # element with that local name, in any namespace.
      #
      # @param doc [Moxml::Document]
      # @param name [String]
      # @return [Moxml::Element, nil]
      def find_element(doc, name)
        return doc.root if doc.root&.name == name

        doc.xpath("//*[local-name()='#{name}']").first
      end

      # Serialize an element as a self-contained document: a sub-element
      # inherits its namespace declarations from an ancestor, and `to_xml`
      # does not write them.
      #
      # @param element [Moxml::Element]
      # @return [String]
      def element_xml(element)
        declared = element.namespace_definitions.map(&:prefix)
        element.in_scope_namespaces.each do |ns|
          next if declared.include?(ns.prefix)

          element.add_namespace(ns.prefix, ns.uri)
        end
        element.to_xml
      end

      # @param rfc [String] RFC XML
      # @return [String] bibdata XML
      def rfc_bibdata_xml(rfc)
        require_relative "../ietf"
        require_relative "../ietf/bibxml_parser"
        Relaton::Ietf::BibXMLParser.parse_rfc(rfc).to_xml(bibdata: true)
      end

      def concatenate_and_write_to_files
        write_to_file(bibcollection.send(output_type))
      end

      def split_and_write_to_files
        output_dir = outdir || build_dirname(source)

        relaton_collection.items.each do |content|
          name = build_filename(nil, content.docidentifier)
          find_available_bibrxl_file(name, output_dir, content)
          write_to_file(content.send(output_type), output_dir, name)
        end
      end

      def find_available_bibrxl_file(name, _ouputdir, content)
        if options[:extension] == "yaml" || options[:extension] == "yml"
          bib_rxl = Pathname.new([outdir, name].join("/")).sub_ext(".rxl")
          content.bib_rxl = bib_rxl.to_s if File.file?(bib_rxl)
        end
      end

      def output_type(ext = options[:extension])
        ext ||= File.extname(outfile)[1..-1] if outfile
        case ext
        when "rxl", "xml"
          :to_xml
        when "yml", "yaml"
          :to_yaml
        else
          puts "[relaton-cli] the given extension of '#{ext}' is "\
          "not supported. Use 'rxl'."
          :to_xml
        end
      end

      # Create a bibdata instance from the XML,
      # while also adding file paths of related artifacts
      # as URI elements to the bibdata instance.
      #
      # @param xml [String] bibdata XML
      # @param file [String] path to file
      # @return [Relaton::Bibdata]
      def bibdata_instance(xml, file)
        bibdata = Relaton::Bibdata.from_xml xml
        build_bibdata_relaton(bibdata, file) if bibdata

        bibdata
      end

      # For each file type, add to the bibdata:
      #   - a URI element that points to the file of that file type
      #
      # The URI element generation is skipped if the file does not exist.
      #
      # @param bibdata [Relaton::Bibdata]
      # @param file [String] path to file
      def build_bibdata_relaton(bibdata, file)
        ["xml", "pdf", "doc", "html", "rxl", "txt"].each do |type|
          file = Pathname.new(file).sub_ext(".#{type}")
          bibdata.send("#{type}=", file.to_s) if File.file?(file)
        end
      end

      def convert_rxl_to_xml
        select_files_with("{rxl}").map do |file|
          { file: file, content: File.read(file, encoding: "utf-8") }
        end
      end

      def convert_yamls_to_xml
        select_files_with("yaml").map do |file|
          { file: file, content: YAMLConvertor.to_xml(file, write: false) }
        end
      end

      def convert_xml_to_xml
        select_files_with("{xml}").map do |file|
          { file: file, content: File.read(file, encoding: "utf-8") }
        end
      end

      def select_files_with(extension)
        files = File.join(source, "**", "*.#{extension}")
        Dir[files].reject { |file| File.directory?(file) }
      end

      def write_to_file(content, directory = nil, output_file = nil)
        file_with_dir = [directory, output_file || outfile].compact.join("/")
        File.open(file_with_dir, "w:utf-8") { |file| file.write(content) }
      end

      def build_dirname(filename)
        basename = File.basename(filename)&.gsub(/.(xml|rxl)/, "")
        directory_name = sanitize_string(basename)
        FileUtils.mkdir_p(directory_name) # unless File.exists?(directory_name)

        directory_name
      end

      def build_filename(file, identifier = nil, ext = "rxl")
        identifier ||= Pathname.new(File.basename(file.to_s, ".xml")).to_s
        [sanitize_string(identifier), options[:extension] || ext].join(".")
      end

      def sanitize_string(string)
        clean_string = replace_bad_characters(string.downcase)
        clean_string.gsub(/^\s+/, "").gsub(/\s+$/, "").gsub(/\s+/, "-")
      end

      def replace_bad_characters(string)
        bad_chars = ["/", "\\", "?", "%", "*", ":", "|", '"', "<", ">", ".", " "]
        bad_chars.reduce(string.downcase) { |res, char| res.gsub(char, "-") }
      end
    end
  end
end
