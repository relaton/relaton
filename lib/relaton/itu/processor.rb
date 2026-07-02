require "relaton/core/processor"

module Relaton
  module Itu
    class Processor < Relaton::Core::Processor
      def initialize
        @short = :relaton_itu
        @prefix = "ITU"
        @defaultprefix = %r{^ITU\s}
        @idtype = "ITU"
        @datasets = %w[itu-r]
      end

      # @param code [String]
      # @param date [String, nil] year
      # @param opts [Hash]
      # @return [Relaton::Itu::ItemData, nil]
      def get(code, date, opts)
        require_relative "../itu"
        Bibliography.get(code, date, opts)
      end

      #
      # Fetch all the documents from https://extranet.itu.int/brdocsearch/
      #
      # @param [String] source source name (itu-r)
      # @param [Hash] opts
      # @option opts [String] :output directory to output documents, default is data
      # @option opts [String] :format output format, default is yaml
      #
      def fetch_data(source, opts)
        require_relative "data_fetcher"
        DataFetcher.fetch(source, **opts)
      end

      # @param xml [String]
      # @return [Relaton::Itu::ItemData]
      def from_xml(xml)
        require_relative "../itu"
        Item.from_xml xml
      end

      # @param yaml [Hash]
      # @return [Relaton::Itu::ItemData]
      def from_yaml(yaml)
        require_relative "../itu"
        Item.from_yaml yaml
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        require_relative "../itu"
        @grammar_hash ||= Itu.grammar_hash
      end

      #
      # Remove index file
      #
      def remove_index_file
        require_relative "../itu"
        Relaton::Index.find_or_create(:itu, url: true, file: "#{INDEXFILE}.yaml").remove_file
      end
    end
  end
end
