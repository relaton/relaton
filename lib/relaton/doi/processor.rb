require "relaton/processor"

module Relaton
  module Doi
    class Processor < Relaton::Processor
      attr_reader :idtype

      def initialize
        @short = :relaton_doi
        @prefix = "DOI"
        @defaultprefix = %r{^doi:}
        @idtype = "DOI"
        # @datasets = %w[bipm-data-outcomes bipm-si-brochure]
      end

      # @param code [String] DOI
      # @param date [String, nil] year
      # @param opts [Hash]
      # @return [RelatonBib::BibliographicItem]
      def get(code, _date, _opts)
        Crossref.get(code)
      end

      #
      # @param [String] source source name
      # @param [Hash] opts
      # @option opts [String] :output directory to output documents
      # @option opts [String] :format
      #
      # def fetch_data(source, opts)
      #   DataFetcher.fetch(source, **opts)
      # end

      # @param xml [String]
      # @return [Bib::ItemData]
      def from_xml(xml)
        ::Relaton::Bib::Item.from_xml xml
      end

      # @param yaml [String]
      # @return [Bib::ItemData]
      def hash_to_bib(yaml)
        ::Relaton::Bib::Item.from_yaml yaml
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        @grammar_hash ||= ::Relaton::Doi.grammar_hash
      end

      # Returns number of threads
      # @return [Integer]
      def threads
        2
      end
    end
  end
end
