require_relative "../core"
require_relative "../eu"

module Relaton
  module Eu
    #
    # Crawl every EU regulation, directive and decision from CELLAR into a
    # data repo: one document a act and the pubid `index-v2`.
    #
    # CELLAR is read one year at a time (`Cellar#each_row`), from the first
    # year of the Official Journal to this year. A page that keeps failing
    # raises before the index is written, so with `prune: true` a failed run
    # publishes nothing.
    #
    class DataFetcher < Core::DataFetcher
      SOURCES = %w[eu-cellar].freeze
      # The first year of the Official Journal (of the ECSC).
      FIRST_YEAR = 1952

      def fetch(source = nil)
        unless SOURCES.include? source
          raise ArgumentError,
                "Unknown source `#{source}`, expected one of #{SOURCES}"
        end

        @keys = {}
        # Every run writes the whole corpus, so the index starts empty: a row
        # an earlier run wrote for an act that is now skipped would outlive
        # its pruned file.
        index.remove_all
        (FIRST_YEAR..Date.today.year).each do |year|
          cellar.each_row(year) { |row| parse_row row }
        end
        index.save
        report_errors
      end

      def index
        # `pubid_class:` on the producer too: FileIO#save calls `to_hash` only
        # for instances of it.
        @index ||= Relaton::Index.find_or_create(
          :eu, file: "#{INDEXFILE}.yaml", pubid_class: ::Pubid::Eu::Identifier
        )
      end

      def log_error(msg)
        Util.error msg
      end

      private

      def cellar
        @cellar ||= Cellar.new
      end

      #
      # Write one work and index it. A work the flavor does not cover (a
      # corrigendum, a work with no ELI of a regulation, directive or
      # decision) gives no item and is skipped. An ELI of a covered act that
      # pubid cannot read is recorded in `@errors`, which `report_errors`
      # sends to the crawl's GitHub issue.
      #
      # Two works of one act keep the first; the second is logged. The act is
      # its ELI, not its printed id: the print order (`number_first`) is not
      # part of the act's identity.
      #
      def parse_row(row)
        parser = Parser.new(row)
        item = parser.parse
        @errors["ELI #{row.dig('eli', 'value')}"] = parser.error if parser.error
        return unless item

        name = parser.pubid.to_s
        act = parser.pubid.to_eli
        celex = row.dig("celex", "value")
        if @keys[act]
          return Util.warn "Skipped CELEX #{celex}: CELEX #{@keys[act]} " \
                           "is the same act", key: name
        end

        @keys[act] = celex
        file = write_unique name, serialize(item)
        index.add_or_update parser.pubid, file
      end

      def to_yaml(bib) = bib.to_yaml
      def to_xml(bib) = bib.to_xml(bibdata: true)
      def to_bibxml(bib) = bib.to_rfcxml
    end
  end
end
