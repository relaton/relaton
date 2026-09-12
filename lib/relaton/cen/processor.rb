require "relaton/core/processor"

module Relaton
  module Cen
    class Processor < Relaton::Core::Processor
      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_cen
        @prefix = "CEN"
        @pubid_flavor = :CenCenelec # global prefixes from Pubid::CenCenelec.prefixes
        @defaultprefix = %r{^(C?EN|ENV|CWA|HD|CR)[\s/]}
        @idtype = "CEN"
      end

      # @param code [String]
      # @param date [String, NilClass] year
      # @param opts [Hash]
      # @return [Relaton::Cen::ItemData]
      def get(code, date, opts)
        require_relative "../cen"
        ::Relaton::Cen::Bibliography.get(code, date, opts)
      end

      # @param xml [String]
      # @return [Relaton::Cen::ItemData]
      def from_xml(xml)
        require_relative "../cen"
        ::Relaton::Cen::Item.from_xml xml
      end

      # @param yaml [String]
      # @return [Relaton::Cen::ItemData]
      def from_yaml(yaml)
        require_relative "../cen"
        ::Relaton::Cen::Item.from_yaml yaml
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        require_relative "../cen"
        @grammar_hash ||= ::Relaton::Cen.grammar_hash
      end
    end
  end
end
