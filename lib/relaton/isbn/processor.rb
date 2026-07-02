require "relaton/core/processor"

module Relaton
  module Isbn
    class Processor < Relaton::Core::Processor
      attr_reader :idtype

      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_isbn
        @prefix = "ISBN"
        @defaultprefix = /^ISBN\s/
        @idtype = "ISBN"
        @datasets = %w[]
      end

      # @param code [String]
      # @param date [String, nil] year
      # @param opts [Hash]
      # @return [Relaton::Bib::Bibitem]
      def get(code, date, opts)
        require_relative "../isbn"
        ::Relaton::Isbn::OpenLibrary.get(code, date, opts)
      end

      #
      # @param xml [String]
      # @return [Relaton::Bib::Bibitem]
      def from_xml(xml)
        require_relative "../isbn"
        ::Relaton::Bib::Bibitem.from_xml xml
      end

      # @param hash [Hash]
      # @return [Relaton::Bib::Bibitem]
      def from_yaml(hash)
        require_relative "../isbn"
        ::Relaton::Bib::Bibitem.from_hash hash
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        require_relative "../isbn"
        @grammar_hash ||= ::Relaton::Isbn.grammar_hash
      end
    end
  end
end
