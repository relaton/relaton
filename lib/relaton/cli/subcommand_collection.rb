require "pubid"
require_relative "util"
require_relative "full_text_search"
require_relative "collection_store"

module Relaton
  module Cli
    class SubcommandCollection < Thor
      include Relaton::Cli
      class_option :verbose, aliases: :v, type: :boolean, desc: "Output warnings"

      desc "create COLLECTION", "Create collection"
      option :dir, aliases: :d, desc: "Directory to store collection. " \
                                      "Default is $HOME/.relaton/collections."
      option :author, desc: "Author"
      option :title, desc: "Title"
      option :doctype, desc: "Documents type"

      def create(file)
        col = Relaton::Bibcollection.new options
        return if store.create file, col

        Util.warn "Collection `#{file}` aready exist"
      end

      desc "info COLLECTION", "View collection information"
      option :dir, aliases: :d, desc: "Directory to store collection. " \
                                      "Default is $HOME/.relaton/collections."

      def info(file) # rubocop:disable Metrics/AbcSize
        col = store.get file
        return Util.warn "Collection `#{file}` does not exist" unless col

        puts "Collection: #{file}"
        puts "Last updated: #{store.updated(file)&.localtime}"
        puts "File size: #{store.size file}"
        puts "Number of items: #{col.items.size}"
        puts "Author: #{col.author}"
        puts "Title: #{col.title}"
      end

      desc "list", "List collections"
      option :dir, aliases: :d, desc: "Directory with collections. Default " \
                                      "is $HOME/.relaton/collections."
      option :entries, aliases: :e, type: :boolean, desc: "Show entries"

      def list
        store.names.each do |name|
          puts name
          puts_entries store.get(name)
        end
      end

      map ls: :list

      desc "get CODE", "Fetch document from collection by ID"
      option :collection, aliases: :c, desc: "Collection to fetch document. " \
        "By default fetch the first match across all collections."
      option :dir, aliases: :d, desc: "Directory with collections. Default " \
                                      "is $HOME/.relaton/collections."
      option :format, aliases: :f, desc: "Output format (xml, abb). " \
        "If not defined the output in a human-readable form."
      option :output, aliases: :o, desc: "Output to the specified file. The " \
        " file's extension (abb, xml) defines output format."

      def get(docid)
        collections.each do |col|
          col[:collection].items.each do |item|
            if item.docidentifier == docid
              output_item(item)
              return
            end
          end
        end
      end

      desc "find TEXT", "Full-text search"
      option :collection, aliases: :c, desc: "Collection to search text. " \
        "By default search across all collections."
      option :dir, aliases: :d, desc: "Directory with collections. Default is " \
                                      "$HOME/.relaton/collections."

      def find(text)
        collections.each do |col|
          searcher = Relaton::FullTextSeatch.new(col[:collection])
          searcher.search text
          if searcher.any?
            puts "Collection: #{col[:file]}"
            searcher.print_results
          end
        end
      end

      map search: :find

      desc "fetch CODE", "Fetch a document and store it into a collection"
      option :type, aliases: :t, required: true,
                    desc: "Type of standard to get bibliographic entry for"
      option :year, aliases: :y, type: :numeric,
                    desc: "Year the standard was published"
      option :"publication-date-before",
        desc: "Fetch only documents published before the specified date " \
          "(e.g. 2008, 2008-02, or 2008-02-02)"
      option :"publication-date-after",
        desc: "Fetch only documents published after the specified date " \
          "(e.g. 2002, 2002-01, or 2002-01-01)"
      option :collection, aliases: :c, required: true,
                          desc: "Collection to store a document"
      option :dir, aliases: :d, desc: "Directory with collections. Default is " \
                                      "$HOME/.relaton/collections."
      option :api, type: :boolean, desc: Relaton::Cli::API_OPTION_DESC

      def fetch(code) # rubocop:disable Metrics/AbcSize
        api_was = apply_api_option options
        opts = {}
        if options[:"publication-date-before"]
          opts[:publication_date_before] = parse_date_option(options[:"publication-date-before"], "--publication-date-before")
        end
        if options[:"publication-date-after"]
          opts[:publication_date_after] = parse_date_option(options[:"publication-date-after"], "--publication-date-after")
        end
        validate_date_range opts[:publication_date_after], opts[:publication_date_before]
        doc = Relaton.db.fetch(code, options[:year]&.to_s, **opts)
        if doc then add_to_collection doc
        else Util.info "No matching bibliographic entry found"
        end
      rescue Relaton::UnknownReferenceError, Relaton::NotInLocalStoreError,
             Relaton::RequestError => e
        # An unknown reference, offline mode with no stored entry
        # (relaton#536) or a transport failure: log the reason, and do not
        # write the collection.
        Util.warn e.message
      rescue Pubid::Errors::Error
        Util.error %("#{code}" is not a recognized standards identifier)
      ensure
        restore_api_option api_was
      end

      desc "import FILE", "Import document or collection from an XML file " \
                          "into another collection"
      option :collection, aliases: :c, required: true,
                          desc: "Collection to store a document. If " \
                                "collection doesn't exist then it'll be created."
      option :dir, aliases: :d, desc: "Directory with collections. Default is " \
                                      "$HOME/.relaton/collections."

      def import(file)
        xml = read_xml file
        if xml.at "relaton-collection"
          imported = import_collection(xml)
          store.update(options[:collection]) do |coll|
            next imported unless coll # a new collection is the imported one

            coll << imported
            coll
          end
        else
          add_to_collection Relaton::Bibdata.from_xml(xml)
        end
      end

      desc "export COLLECTION", "Export collection into XML file"
      option :dir, aliases: :d, desc: "Directory with collections. Default is " \
                                      "$HOME/.relaton/collections."

      def export(file)
        coll = store.get file
        return Util.warn "Collection `#{file}` does not exist" unless coll

        outfile = "#{file.sub(/\.\w+$/, '')}.xml"
        File.write outfile, coll.to_xml(bibdata: true), encoding: "UTF-8"
      end

      private

      # Parse a namespace-free collection XML document.
      # Bibcollection.from_xml expects namespaced docs (via apply_namespace),
      # so we use plain XPath on the namespace-stripped document instead.
      def import_collection(xml)
        title = xml.at("relaton-collection/title")&.text
        author = xml.at_xpath(
          "./relaton-collection/contributor[role/@type='author']"\
          "/organization/name",
        )&.text
        items = xml.xpath("relaton-collection/relation").map do |rel|
          el = rel.at("bibdata") || rel.at("bibitem")
          Relaton::Bibdata.from_xml(el || rel)
        end.compact
        Relaton::Bibcollection.new(title: title, author: author, items: items)
      end

      # @return [String]
      def directory
        options.fetch :dir, File.join(Dir.home, ".relaton/collections")
      end

      # The collections, in a lutaml-store store under `<dir>/v2` (#549).
      # @return [Relaton::Cli::CollectionStore]
      def store
        @store ||= CollectionStore.new directory
      end

      # Adds an item to the `--collection` in one atomic read-modify-write,
      # and creates the collection when it is missing.
      def add_to_collection(item)
        store.update(options[:collection]) do |coll|
          coll ||= Relaton::Bibcollection.new({})
          coll << item
          coll
        end
      end

      # The XML file `import` reads: user input, not a collection.
      # @return [Nokogiri::XML::Document]
      def read_xml(file)
        xml = Nokogiri::XML File.read(file, encoding: "UTF-8")
        xml.remove_namespaces!
        xml
      end

      # @return [Array<Hash>]
      def collections
        store.names(options.fetch(:collection, "*")).filter_map do |name|
          coll = store.get name
          { collection: coll, file: name } if coll
        end
      end

      # Puts document IDs for each item in the collection
      # @param coll [Relaton::Bibcollection]
      def puts_entries(coll)
        return unless options[:entries]

        coll.items.each { |b| puts "  #{b.docidentifier}" }
      end

      # @param item [Relaton::Bibdata]
      def output_item(item)
        case options[:format]
        when "xml" then puts item.to_xml bibdata: true
        when "abb" then puts item.to_asciibib
        else puts_human_readable_item item
        end
        out = case options[:output]
              when /\.abb$/ then item.to_asciibib
              when /\.xml$/ then item.to_xml bibitem: true
              end
        File.write options[:output], out, encoding: "UTF-8" if out
      end

      # @param item [Relaton::Bibdata]
      def puts_human_readable_item(item) # rubocop:disable Metrics/AbcSize
        puts "Document identifier: #{item.docidentifier}"
        puts "Title: #{item.title.first.content}"
        puts "Status: #{item.status.stage}"
        item.date.each { |d| puts "Date #{d.type}: #{d.at || d.from}" }
      end
    end
  end
end
