require "relaton/core/processor"

module Relaton
  module Jcgm
    class Processor < Core::Processor
      attr_reader :idtype

      def initialize
        @short = :relaton_jcgm
        @prefix = "JCGM"
        @defaultprefix = %r{^JCGM\s}
        @idtype = "JCGM"
        @datasets = %w[bipm-data-outcomes]
        # Prefixes come from pubid (Pubid::Jcgm.prefixes => ["JCGM"]); see
        # Core::Processor#prefixes.
        @pubid_flavor = :Jcgm
      end

      # @param code [String]
      # @param date [String, nil] year
      # @param opts [Hash]
      # @return [Relaton::Jcgm::ItemData, nil]
      def get(code, date, opts)
        require_relative "../jcgm"
        Bibliography.get(code, date, opts)
      end

      #
      # Harvest the JCGM meeting proceedings from metanorma/bipm-data-outcomes.
      # Used to (re)generate the relaton-data-jcgm repo; the curated static guides
      # are indexed by that repo's crawler via DataFetcher#add_to_index.
      #
      # @param [String] source source name ("bipm-data-outcomes")
      # @param [Hash] opts
      #
      def fetch_data(source, opts)
        require_relative "data_fetcher"
        DataFetcher.fetch(source, **opts)
      end

      # @param xml [String]
      # @return [Relaton::Jcgm::ItemData]
      def from_xml(xml)
        require_relative "../jcgm"
        Item.from_xml xml
      end

      # @param yaml [String]
      # @return [Relaton::Jcgm::ItemData]
      def from_yaml(yaml)
        require_relative "../jcgm"
        Item.from_yaml yaml
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        require_relative "../jcgm"
        @grammar_hash ||= ::Relaton::Jcgm.grammar_hash
      end

      #
      # Remove index file
      #
      def remove_index_file
        require_relative "../jcgm"
        Relaton::Index.find_or_create(:jcgm, url: true, file: "#{INDEXFILE}.yaml").remove_file
      end
    end
  end
end
