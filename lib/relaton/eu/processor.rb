require_relative "../core/processor"

module Relaton
  module Eu
    class Processor < Relaton::Core::Processor
      attr_reader :idtype

      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_eu
        @prefix = "EU"
        @defaultprefix = /^EU\s/
        @idtype = "EU"
        @datasets = %w[eu-cellar eu-cellar-updates]
        # Db cache key and prefixes: `Pubid::Eu` (pubid 2.0.44, pubid#752).
        @pubid_flavor = :Eu
      end

      # @param code [String, Pubid::Eu::Identifier]
      # @param date [String, nil] year
      # @param opts [Hash]
      # @return [Relaton::Bib::ItemData, nil]
      def get(code, date, opts)
        require_relative "../eu"
        Bibliography.get(code, date, opts)
      end

      # @param source [String] `eu-cellar` (full crawl) or `eu-cellar-updates`
      # @param opts [Hash] `output:`, `format:`
      def fetch_data(source, opts)
        require_relative "data_fetcher"
        DataFetcher.fetch(source, **opts)
      end

      # @param xml [String]
      # @return [Relaton::Bib::ItemData]
      def from_xml(xml)
        require_relative "../eu"
        Bib::Item.from_xml xml
      end

      # @param yaml [String]
      # @return [Relaton::Bib::ItemData]
      def from_yaml(yaml)
        require_relative "../eu"
        Bib::Item.from_yaml yaml
      end

      # @return [String]
      def grammar_hash
        require_relative "../eu"
        @grammar_hash ||= Eu.grammar_hash
      end

      def remove_index_file
        require_relative "../eu"
        Relaton::Index.find_or_create(:eu, url: true,
                                           file: "#{INDEXFILE}.yaml").remove_file
      end
    end
  end
end
