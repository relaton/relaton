require "relaton/core/processor"

module Relaton
  module Doi
    class Processor < Core::Processor
      attr_reader :idtype

      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_doi
        @prefix = "DOI"
        @defaultprefix = %r{^doi:}
        @idtype = "DOI"
      end

      # @param code [String] DOI
      # @param date [String, nil] year
      # @param opts [Hash]
      # @return [RelatonBib::BibliographicItem]
      def get(code, _date, _opts)
        require_relative "../doi"
        Crossref.get(code)
      end

      #
      # @param [String] source source name
      # @param [Hash] opts
      # @option opts [String] :output directory to output documents
      # @option opts [String] :format
      #
      def fetch_data(_source, _opts)
        Util.info "This processor does not support fetching data by source name. Use `get` method with DOI instead."
      end

      # @param xml [String]
      # @return [Bib::ItemData]
      def from_xml(xml)
        require_relative "../doi"
        Bib::Item.from_xml xml
      end

      # @param yaml [String]
      # @return [Bib::ItemData]
      def from_yaml(yaml)
        require_relative "../doi"
        Bib::Item.from_yaml yaml
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        require_relative "../doi"
        @grammar_hash ||= ::Relaton::Doi.grammar_hash
      end

      def remove_index_file
        require_relative "../doi" # defines Util — needed when called cold
        Util.info "This processor does not support index file. No action taken."
      end

      # Returns number of threads
      # @return [Integer]
      def threads = 2
    end
  end
end
