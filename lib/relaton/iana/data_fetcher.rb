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
        docs = []
        Dir["iana-registries/**/*.xml"].each do |file|
          content = File.read file, encoding: "UTF-8"
          collect content, docs if content.include? "<registry"
        rescue StandardError => e
          Util.error "Error: #{e.message}. File: #{file}"
        end
        write_docs docs
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

      # A registry element with no <record> children carries no registry data
      # of its own: IANA wraps some registries in a same-titled <hide/> page
      # (the language-tag-extensions wrapper around its "-1" child), and
      # republishes child registries as standalone pages whose XML is empty
      # (rpki-signed-objects). The saved record for such an element is a
      # slug-titled, dateless duplicate of the registry that holds the
      # records (relaton-iana#8, #9), so it never becomes a document: when a
      # record-bearing document of the same registry id exists, it becomes an
      # index alias to that document's file; otherwise it is dropped.
      RegistryDoc = Struct.new(:bib, :empty, :source)

      def collect(content, docs)
        xml = Moxml.parse(content)
        registry = xml.at_xpath("/xmlns:registry", NS)
        doc = Parser.parse registry, nil, @errors
        docs << RegistryDoc.new(doc, recordless?(registry), content) if doc
        registry.xpath("./xmlns:registry", NS).each do |r|
          child = Parser.parse r, doc, @errors
          docs << RegistryDoc.new(child, recordless?(r), content) if child
        end
      end

      def recordless?(registry_el)
        registry_el.xpath("./xmlns:record", NS).empty?
      end

      def write_docs(docs)
        saved = {}
        docs.each do |d|
          if d.empty
            Util.warn "Registry #{d.bib.docnumber} has no records; skipping"
            next
          end
          # The fetched XML content bounds the registry's record, so an
          # unchanged source skips the parse and the write (the digest
          # ledger); the aliased file still has to resolve for the alias
          # phase. The content is only digested when the ledger is on.
          if @digest_ledger && d.source && unchanged?(d.bib.docnumber, d.source)
            saved[d.bib.id] = ledger_file(d.bib.docnumber)
            next
          end
          file = save_doc d.bib
          note_digest d.bib.docnumber, d.source, file: file if @digest_ledger && d.source
          saved[d.bib.id] = file if file
        end
        docs.select(&:empty).each do |d|
          next unless (file = saved[d.bib.id])

          Util.warn "Registry #{d.bib.docnumber} has no records; aliasing #{file}"
          add_to_index d.bib.docnumber, file
        end
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
        record_written file
        file
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
