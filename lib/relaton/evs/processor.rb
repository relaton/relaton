require "relaton/core/processor"

module Relaton
  module Evs
    class Processor < Relaton::Core::Processor
      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_evs
        @prefix = "EVS"
        @pubid_flavor = :Evs
        @defaultprefix = %r{^EVS[\s-]}
        @idtype = "EVS"
      end

      # @param code [String]
      # @param date [String, NilClass] year
      # @param opts [Hash]
      # @return [Relaton::Evs::ItemData]
      def get(code, date, opts)
        require_relative "../evs"
        ::Relaton::Evs::Bibliography.get(code, date, opts)
      end

      # `Bibliography.get` applies a year to the document the reference names.
      def fold_year(pubid, year)
        fold_year_on_root pubid, year
      end

      # @param xml [String]
      # @return [Relaton::Evs::ItemData]
      def from_xml(xml)
        require_relative "../evs"
        ::Relaton::Evs::Item.from_xml xml
      end

      # @param yaml [String]
      # @return [Relaton::Evs::ItemData]
      def from_yaml(yaml)
        require_relative "../evs"
        ::Relaton::Evs::Item.from_yaml yaml
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        require_relative "../evs"
        @grammar_hash ||= ::Relaton::Evs.grammar_hash
      end
    end
  end
end
