require_relative "../cen"

module Relaton
  module Cen
    class Processor < Relaton::Core::Processor
      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_cen
        @prefix = "CEN"
        @defaultprefix = %r{^(C?EN|ENV|CWA|HD|CR)[\s/]}
        @idtype = "CEN"
      end

      # @param code [String]
      # @param date [String, NilClass] year
      # @param opts [Hash]
      # @return [RelatonBib::BibliographicItem]
      def get(code, date, opts)
        Bibliography.get(code, date, opts)
      end

      # @param xml [String]
      # @return [RelatonBib::BibliographicItem]
      def from_xml(xml)
        Item.from_xml xml
      end

      # @param yaml [String]
      # @return [RelatonBib::BibliographicItem]
      def from_yaml(yaml)
        Item.from_yaml yaml
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        @grammar_hash ||= Cen.grammar_hash
      end
    end
  end
end
