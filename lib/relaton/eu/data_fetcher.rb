require "time"
require_relative "../core"
require_relative "../eu"

module Relaton
  module Eu
    #
    # Crawl every EU regulation, directive and decision from CELLAR into a
    # data repo: one document a act and the pubid `index-v2`.
    #
    # Two sources:
    #
    # - `eu-cellar`, the full crawl: CELLAR is read one year at a time
    #   (`Cellar#each_row`), from the first year of the Official Journal to
    #   this year, into an empty index. Run it with `prune: true`, so an act
    #   CELLAR dropped loses its file.
    # - `eu-cellar-updates`: only the works CELLAR changed since the last
    #   run (`Cellar#each_modified_row`), written over the existing data and
    #   added to the existing index. It cannot see a work CELLAR deleted, nor
    #   a change that does not touch the work (an author's new label), so the
    #   full crawl still runs from time to time. It refuses `prune: true`.
    #
    # Both write the start time of the run to SINCE_FILE; the next update
    # run reads from one day before it. A page that keeps failing raises
    # before the index and SINCE_FILE are written, so a failed run
    # publishes nothing and the next one reads the same changes again.
    #
    class DataFetcher < Core::DataFetcher
      FULL = "eu-cellar".freeze
      UPDATES = "eu-cellar-updates".freeze
      SOURCES = [FULL, UPDATES].freeze
      # The first year of the Official Journal (of the ECSC).
      FIRST_YEAR = 1952
      # The start time of the last run that finished, in UTC (ISO 8601).
      SINCE_FILE = "cellar-since.txt".freeze
      # An update run reads from this long before the last run started:
      # CELLAR's clock and the crawler's need not agree, and a work can be
      # changed while a run reads its year.
      OVERLAP = 24 * 60 * 60

      def fetch(source = nil)
        unless SOURCES.include? source
          raise ArgumentError,
                "Unknown source `#{source}`, expected one of #{SOURCES}"
        end

        started = Time.now.utc
        @keys = {}
        source == FULL ? fetch_all : fetch_updates
        index.save
        File.write SINCE_FILE, "#{started.strftime('%Y-%m-%dT%H:%M:%SZ')}\n"
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

      def fetch_all
        # Every full run writes the whole corpus, so the index starts empty:
        # a row an earlier run wrote for an act that is now skipped would
        # outlive its pruned file.
        index.remove_all
        (FIRST_YEAR..Date.today.year).each do |year|
          cellar.each_row(year) { |row| parse_row row }
        end
      end

      def fetch_updates
        if prune
          raise ArgumentError, "#{UPDATES} writes only the changed acts; " \
                               "prune would delete every other act. Prune " \
                               "with #{FULL}."
        end

        cellar.each_modified_row(last_run - OVERLAP) { |row| parse_row row }
      end

      # @return [Time] the start time of the last run, from SINCE_FILE
      def last_run
        unless File.exist? SINCE_FILE
          raise ArgumentError, "#{UPDATES} needs #{SINCE_FILE}, which a " \
                               "finished #{FULL} run writes; run #{FULL} first"
        end

        Time.iso8601 File.read(SINCE_FILE, encoding: "UTF-8").strip
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
