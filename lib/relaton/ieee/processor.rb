require "relaton/core/processor"

module Relaton
  module Ieee
    class Processor < Core::Processor
      attr_reader :idtype

      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_ieee
        @prefix = "IEEE"
        @defaultprefix = %r{^(?:(?:(?:ANSI|NACE)/)?IEEE|ANSI|AIEE|ASA|NACE|IRE)\s}
        @idtype = "IEEE"
        @datasets = %w[ieee-rawbib]
      end

      # @param code [String]
      # @param date [String, NilClass] year
      # @param opts [Hash]
      # @return [Relaton::Ieee::ItemData, nil]
      def get(code, date, opts)
        require_relative "../ieee"
        Bibliography.get(code, date, opts)
      end

      #
      # Fetch all the documents from ./iee-rawbib directory
      #
      # @param [String] source source name
      # @param [Hash] opts
      # @option opts [String] :output directory to output documents
      # @option opts [String] :format
      #
      def fetch_data(source, opts)
        require_relative "data_fetcher"
        DataFetcher.fetch(source, **opts)
      end

      # @param xml [String]
      # @return [Relaton::Ieee::ItemData]
      def from_xml(xml)
        require_relative "../ieee"
        Item.from_xml xml
      end

      # @param yaml [String]
      # @return [Relaton::Ieee::ItemData]
      def hash_to_bib(yaml)
        require_relative "../ieee"
        Item.from_yaml yaml
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        require_relative "../ieee"
        @grammar_hash ||= Ieee.grammar_hash
      end

      #
      # Remove index file
      #
      def remove_index_file
        require_relative "../ieee"
        Relaton::Index.find_or_create(:ieee, url: true, file: "#{INDEXFILE}.yaml").remove_file
      end
    end
  end
end
