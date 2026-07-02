require "relaton/core/processor"

module Relaton
  module Iana
    class Processor < Relaton::Core::Processor
      attr_reader :idtype

      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_iana
        @prefix = "IANA"
        @defaultprefix = %r{^IANA\s}
        @idtype = "IANA"
        @datasets = %w[iana-registries]
      end

      # @param code [String]
      # @param date [String, NilClass] year
      # @param opts [Hash]
      # @return [Relaton::Iana::ItemData, nil]
      def get(code, date, opts)
        require_relative "../iana"
        Bibliography.get(code, date, opts)
      end

      #
      # Fetch all the documents from https://github.com/ietf-ribose/iana-registries
      #
      # @param [String] source source name
      # @param [Hash] opts
      # @option opts [String] :output directory to output documents
      # @option opts [String] :format output format, "xml" or "yaml"
      #
      def fetch_data(source, opts)
        require_relative "data_fetcher"
        DataFetcher.fetch(source, **opts)
      end

      # @param xml [String]
      # @return [Relaton::Iana::ItemData]
      def from_xml(xml)
        require_relative "../iana"
        Item.from_xml xml
      end

      # @param yaml [String]
      # @return [RelatonIana::ItemData]
      def from_yaml(yaml)
        require_relative "../iana"
        Item.from_yaml yaml
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        require_relative "../iana"
        @grammar_hash ||= ::Relaton::Iana.grammar_hash
      end

      #
      # Remove index file
      #
      def remove_index_file
        require_relative "../iana"
        Relaton::Index.find_or_create(:iana, url: true, file: "#{INDEXFILE}.yaml").remove_file
      end
    end
  end
end
