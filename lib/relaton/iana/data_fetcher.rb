require "relaton/core"
require_relative "../iana"
require_relative "parser"

module Relaton
  module Iana
    class DataFetcher < Core::DataFetcher
      #
      # Parse documents
      #
      def log_error(msg)
        Util.error msg
      end

      def fetch(_source = nil)
        Dir["iana-registries/**/*.xml"].each do |file|
          content = File.read file, encoding: "UTF-8"
          parse(content) if content.include? "<registry"
        rescue StandardError => e
          Util.error "Error: #{e.message}. File: #{file}"
        end
        index.save
        report_errors
      end

      private

      def index
        @index ||= Relaton::Index.find_or_create :iana, file: "#{INDEXFILE}.yaml",
                                                        pubid_class: ::Pubid::Iana::Identifier
      end

      #
      # Add a document to the pubid-keyed index-v2.
      #
      # Stores the Pubid::Iana identifier object (not its hash): with
      # pubid_class set, Relaton::Index sorts the index by the id's number on
      # save and serializes each id to its `_type: pubid:iana:registry` hash.
      #
      # The rescue is load-bearing. Relaton::Index rejects the WHOLE index if a
      # single row fails to deserialize, so a slug pubid cannot parse has to be
      # skipped here rather than raise and abort the crawl.
      #
      # @param [String] docnumber bare registry slug, `registry[/sub-registry]`
      # @param [String] file path of the document file
      #
      def add_to_index(docnumber, file)
        index.add_or_update ::Pubid::Iana::Identifier.parse(docnumber), file
      rescue StandardError => e
        Util.warn "Skipping index entry for `#{docnumber}` (#{file}): #{e.message}"
      end

      def parse(content)
        xml = Nokogiri::XML(content)
        registry = xml.at("/xmlns:registry")
        doc = Parser.parse registry, nil, @errors
        save_doc doc
        registry.xpath("./xmlns:registry").each { |r| save_doc Parser.parse(r, doc, @errors) }
      end

      #
      # Save document to file
      #
      # @param [RelatonIana::IanaBibliographicItem, nil] bib bibliographic item
      #
      def save_doc(bib) # rubocop:disable Metrics/MethodLength
        return unless bib

        # Two distinct registries can sanitize to one filename (`/` and `-` both
        # collapse to `-`), e.g. `rpki/signed-objects` and `rpki-signed-objects`.
        # Take a path of our own rather than overwriting the other document, but
        # keep the clash visible in the crawl log.
        file = unique_output_file bib.docnumber
        if @files.include? file
          # A reserved path only ever belongs to one docnumber, so this is the
          # same document again: a genuine duplicate, not a collision. Checked
          # FIRST, because a disambiguated path stays != output_file forever.
          Util.warn "File #{file} already exists. Document: #{bib.docnumber}"
        elsif file != output_file(bib.docnumber)
          Util.warn "File #{output_file bib.docnumber} already exists. " \
                    "Document: #{bib.docnumber}. Writing #{file} instead."
        end
        @files << file
        add_to_index bib.docnumber, file
        File.write file, serialize(bib), encoding: "UTF-8"
      end

      def to_xml(bib)
        bib.to_xml(bibdata: true)
      end

      def to_yaml(bib)
        bib.to_yaml
      end

      def to_bibxml(bib)
        bib.to_rfcxml
      end
    end
  end
end
