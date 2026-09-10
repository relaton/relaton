require "relaton/core"

module Relaton
  module Xsf
    class DataFetcher < Relaton::Core::DataFetcher
      # `Core::DataFetcher#log_error` raises unless the flavor overrides it, so
      # `report_errors` is unusable without this. (The ECMA precedent.)
      def log_error(msg)
        Util.error msg
      end

      def index
        # `pubid_class:` on the producer too: FileIO#save only calls `to_hash`
        # when the value is an instance of it, so without it the crawl writes
        # v1-shaped rows under a v2 name, silently.
        @index ||= Relaton::Index.find_or_create(
          :xsf, file: "#{INDEXFILE}.yaml", pubid_class: ::Pubid::Xsf::Identifier
        )
      end

      def fetch(_source = nil)
        agent = Mechanize.new
        resp = agent.get "https://xmpp.org/extensions/refs/"
        resp.xpath("//a[contains(@href, 'XEP-')]").each do |link|
          doc = agent.get link[:href]
          bib = Relaton::Bib::Converter::BibXml.to_item doc.body
          save_doc bib
        rescue StandardError => e
          Util.warn "Failed to parse #{link[:href]}: #{e.message}"
        end
        index.save
        report_errors
      end

      def save_doc(bib)
        return unless bib

        bib.ext ||= Relaton::Bib::Ext.new
        bib.ext.flavor = "xsf"

        docid = bib.docidentifier.detect(&:primary) || bib.docidentifier.first
        id = docid&.content
        return unless id

        # Distinct docids can sanitize to one filename; take a path of our own
        # rather than overwriting the other document (Core#unique_output_file).
        file = unique_output_file id
        if @files.include? file
          # Same reserved path == same id: a genuine duplicate. Checked FIRST,
          # because a disambiguated path stays != output_file forever.
          Util.warn "File #{file} already exists"
        elsif file != output_file(id)
          Util.warn "File #{output_file id} already exists; writing #{file} instead"
        end
        @files << file
        File.write file, serialize(bib), encoding: "UTF-8"
        add_to_index id, file
      end

      #
      # Index a document under its pubid, skipping one pubid cannot parse.
      #
      # This guard is not optional here. One unparseable row does not fail that
      # row: `Relaton::Index` declares the **whole file** corrupt, deletes it,
      # and hands back an **empty** index. Measured — 519 good rows plus one
      # unparseable id loads as 0 rows, and the only trace is two INFO lines
      # ("Wrong structure of file …", "Considering … corrupt, removing it"). So
      # indexing one bad row silently breaks every XSF lookup, not just its own.
      #
      # A rejection is recorded in `@errors`, which `report_errors` turns into a
      # GitHub issue at the end of the crawl (the 3GPP/ECMA precedent). Nothing
      # in the published corpus trips it today: pubid parses all 520 rows,
      # including the two entries that are pages rather than XEPs — the XEP
      # repository's `README` and its `xep-xxxx` template, which pubid accepts
      # as the literal numbers `README` and `xxxx` while still rejecting
      # anything else non-numeric (`XEP banana`, or a typo like `XEP 00O1`).
      # So a recorded error now means something genuinely new appeared, which
      # is exactly when an issue is worth filing.
      #
      # The data file is written either way, so a document that cannot be
      # indexed is unindexed, never lost.
      #
      # @param docid [String]
      # @param file [String]
      #
      def add_to_index(docid, file)
        index.add_or_update ::Pubid::Xsf::Identifier.parse(docid), file
      rescue StandardError => e
        @errors[docid] =
          "Unparseable primary id `#{docid}` was not indexed (#{e.message})"
      end

      def to_yaml(bib)
        bib.to_yaml
      end

      def to_xml(bib)
        bib.to_xml bibdata: true
      end

      def to_bibxml(bib)
        bib.to_rfcxml
      end
    end
  end
end
