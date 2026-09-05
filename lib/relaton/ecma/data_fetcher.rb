# frozen_string_literal: true

require "English"
require "mechanize"
require "relaton/core"
require_relative "../ecma"
require_relative "parser_common"
require_relative "page_fetcher"
require_relative "standard_parser"
require_relative "memento_parser"
require_relative "edition_parser"
require_relative "data_parser"

module Relaton
  module Ecma
    class DataFetcher < Core::DataFetcher
      URL = "https://www.ecma-international.org/publications-and-standards/"
      SOURCES = %w[standards technical-reports mementos].freeze

      def index
        # `pubid_class:` on the producer too: FileIO#save only calls `to_hash`
        # for instances of it, so without it the crawl writes v1-shaped rows
        # under a v2 name, silently.
        @index ||= Relaton::Index.find_or_create(
          :ecma, file: "#{INDEXFILE}.yaml", pubid_class: ::Pubid::Ecma::Identifier
        )
      end

      def log_error(msg)
        Util.error msg
      end

      def agent
        @agent ||= Mechanize.new.tap { |a| a.user_agent_alias = Mechanize::AGENT_ALIASES.keys.sample }
      end

      # @param bib [Relaton::Ecma::ItemData]
      def write_file(bib)
        # Two distinct ids can sanitize to one filename, in which case the
        # second document used to be dropped outright. Give it a path of its
        # own; a genuine duplicate (same id) still resolves to one path and is
        # still skipped.
        file = unique_output_file filename_id(bib)
        # A reserved path only ever belongs to one id, so a hit here is the same
        # document again. Checked FIRST: a disambiguated path stays != filename
        # forever, so gating this on that comparison would make a repeat of a
        # disambiguated id skip the skip and overwrite its own file.
        if @files.include? file
          Util.warn "Duplicate file #{file}"
          return
        end

        Util.warn "Duplicate file #{filename bib}; writing #{file} instead" if file != filename(bib)
        @files << file
        File.write file, serialize(bib), encoding: "UTF-8"
        add_to_index bib, file
      end

      #
      # Index the document, or record why it could not be indexed.
      #
      # An id pubid cannot rebuild is recorded in `@errors` — the inherited
      # `report_errors` logs a String value as the message, and its GhIssue
      # channel opens a GitHub issue at the end of the crawl — and the row is
      # skipped rather than indexed unparsed: `Relaton::Index` rejects the WHOLE
      # index if a single row fails to deserialize, and its sort calls
      # `.root.number` on every id. The data file is already written by the
      # caller, so the document is unindexed, never lost. (The 3GPP/W3C shape.)
      #
      # @param bib [Relaton::Ecma::ItemData]
      # @param file [String] path the document was written to
      #
      def add_to_index(bib, file)
        id = index_id bib
        return index.add_or_update(id, file) if id

        docid = bib.docidentifier[0]&.content || file
        @errors[docid.to_s] = "Unparseable primary id `#{docid}` was not indexed (#{file})"
      end

      def filename(bib)
        output_file filename_id(bib)
      end

      # The docid the filename is derived from.
      def filename_id(bib)
        id = bib.docidentifier[0].content
        id += " #{bib.edition.content}" if bib.edition
        locality = locality_with_volume bib
        id += " #{locality.reference_from}" if locality
        id
      end

      #
      # The index key: a `Pubid::Ecma::Identifier` carrying the number, the
      # edition and the volume.
      #
      # Built from the MODEL, never from a rendered string — the same three
      # fields `#filename_id` reads — so the crawl cannot lose a component to a
      # parse or to a render default. The base identifier is the docidentifier's
      # own pubid, **duplicated** first: `edition` and `volume` are index
      # metadata, and every `ECMA-269` volume file carries the bare
      # `docidentifier: ECMA-269`, so setting them on the shared object would
      # promote the document's own printed id to the index form.
      #
      # @param bib [Relaton::Ecma::ItemData]
      # @return [Pubid::Ecma::Identifier, nil] nil if pubid rejects the docid
      #
      def index_id(bib)
        pubid = bib.docidentifier[0]&.pubid&.dup
        return unless pubid

        pubid.edition = bib.edition.content if bib.edition
        locality = locality_with_volume bib
        pubid.volume = locality.reference_from if locality
        pubid
      end

      def locality_with_volume(bib)
        bib.extent.each do |e|
          locality = e.locality.find { |l| l.type == "volume" }
          return locality if locality
        end
        nil
      end

      def to_xml(bib) = bib.to_xml(bibdata: true)
      def to_yaml(bib) = bib.to_yaml
      def to_bibxml(bib) = bib.to_rfcxml

      # @param hit [Nokogiri::XML::Element]
      def parse_page(hit) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        DataParser.new(hit, @errors).parse.each { |item| write_file item }
      end

      # @param type [String]
      def html_index(type) # rubocop:disable Metrics/MethodLength
        result = agent.get "#{URL}#{type}/"
        # @last_call_time = Time.now
        result.xpath(
          "//li/span[1]/a",
          "//div[contains(@class, 'entry-content-wrapper')][.//a[.='Download']]",
        ).each do |hit|
          parse_page(hit)
        rescue StandardError => e
          Util.error { "#{e.message}\n#{e.backtrace}" }
        end
      end

      #
      # Fetch data from Ecma website.
      #
      # @return [void]
      #
      def fetch(_ = nil)
        SOURCES.each { |source| html_index source }
        index.save
        report_errors
      end
    end
  end
end
