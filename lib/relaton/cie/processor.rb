require "relaton/core/processor"

module Relaton
  module Cie
    class Processor < Relaton::Core::Processor
      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_cie
        @prefix = "CIE"
        @defaultprefix = /^CIE(-|\s)/
        @idtype = "CIE"
        @datasets = %w[cie-techstreet]
      end

      # @param code [String]
      # @param date [String, NilClass] year
      # @param opts [Hash]
      # @return [Relaton::Cie::ItemData, nil]
      def get(code, date, opts)
        require_relative "../cie"
        Bibliography.get(code, date, opts)
      end

      #
      # Fetch all the docukents from a source
      #
      # @param [String] _source source name
      # @param [Hash] opts
      # @option opts [String] :output directory to output documents
      # @option opts [String] :format
      #
      def fetch_data(_source, opts)
        require_relative "data_fetcher"
        DataFetcher.fetch(**opts)
      end

      # @param xml [String]
      # @return [Relaton::Cie::ItemData]
      def from_xml(xml)
        require_relative "../cie"
        Item.from_xml xml
      end

      # @param hash [String]
      # @return [Relaton::Cie::ItemData]
      def from_yaml(yaml)
        require_relative "../cie"
        Item.from_yaml yaml
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        require_relative "../cie"
        @grammar_hash ||= Cie.grammar_hash
      end

      #
      # Remove index file
      #
      def remove_index_file
        require_relative "../cie"
        Relaton::Index.find_or_create(:cie, url: true, file: "#{INDEXFILE}.yaml").remove_file
      end
    end
  end
end
