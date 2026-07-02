require "relaton/core/processor"

module Relaton
  module Ogc
    class Processor < Core::Processor
      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_ogc
        @prefix = "OGC"
        @defaultprefix = %r{^OGC\s}
        @idtype = "OGC"
        @datasets = %w[ogc-naming-authority]
      end

      # @param code [String]
      # @param date [String, nil]
      # @param opts [Hash]
      # @return [Relaton::Ogc::ItemData]
      def get(code, date, opts)
        require_relative "../ogc"
        Bibliography.get(code, date, opts)
      end

      # @param source [String]
      # @param opts [Hash]
      def fetch_data(_source, opts)
        require_relative "data_fetcher"
        DataFetcher.fetch(**opts)
      end

      # @param xml [String]
      # @return [Relaton::Ogc::ItemData]
      def from_xml(xml)
        require_relative "../ogc"
        Item.from_xml xml
      end

      # @param yaml [String]
      # @return [Relaton::Ogc::ItemData]
      def from_yaml(yaml)
        require_relative "../ogc"
        Item.from_yaml yaml
      end

      # @return [String]
      def grammar_hash
        require_relative "../ogc"
        @grammar_hash ||= Relaton::Ogc.grammar_hash
      end

      def remove_index_file
        require_relative "../ogc"
        Relaton::Index.find_or_create(
          :ogc, url: true, file: "#{INDEXFILE}.yaml",
        ).remove_file
      end
    end
  end
end
