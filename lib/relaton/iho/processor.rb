require "relaton/core"
require_relative "../iho"

module Relaton
  module Iho
    class Processor < Core::Processor
      attr_reader :idtype

      def initialize
        @short = :relaton_iho
        @prefix = "IHO"
        @defaultprefix = %r{^IHO\s}
        @idtype = "IHO"
      end

      # @param code [String]
      # @param date [String, nil] year
      # @param opts [Hash]
      # @return [Relaton::Iho::ItemData, nil]
      def get(code, date, opts)
        Bibliography.get(code, date, opts)
      end

      # @param xml [String]
      # @return [Relaton::Iho::ItemData]
      def from_xml(xml)
        Item.from_xml xml
      end

      # @param yaml [String]
      # @return [Relaton::Iho::ItemData]
      def hash_to_bib(yaml)
        Item.from_yaml(yaml)
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        @grammar_hash ||= ::Relaton::Iho.grammar_hash
      end

      #
      # Remove index file
      #
      def remove_index_file
        Relaton::Index.find_or_create(:iho, url: true, file: "#{INDEXFILE}.yaml}").remove_file
      end
    end
  end
end
