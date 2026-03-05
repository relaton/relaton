require "relaton-core"
require_relative "../isbn"

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
        ::Relaton::Isbn::OpenLibrary.get(code, date, opts)
      end

      #
      # @param xml [String]
      # @return [Relaton::Bib::Bibitem]
      def from_xml(xml)
        ::Relaton::Bib::Bibitem.from_xml xml
      end

      # @param hash [Hash]
      # @return [Relaton::Bib::Bibitem]
      def from_yaml(hash)
        ::Relaton::Bib::Bibitem.from_hash hash
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        @grammar_hash ||= ::Relaton::Isbn.grammar_hash
      end
    end
  end
end
