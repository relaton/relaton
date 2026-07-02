require "relaton/core/processor"

module Relaton
  module Oiml
    class Processor < Core::Processor
      attr_reader :idtype

      def initialize
        @short = :relaton_oiml
        @prefix = "OIML"
        @defaultprefix = %r{^OIML\s}
        @idtype = "OIML"
      end

      # @param code [String]
      # @param date [String, nil] year
      # @param opts [Hash]
      # @return [Relaton::Oiml::ItemData, nil]
      def get(code, date, opts)
        require_relative "../oiml"
        Bibliography.get(code, date, opts)
      end

      # @param xml [String]
      # @return [Relaton::Oiml::ItemData]
      def from_xml(xml)
        require_relative "../oiml"
        Item.from_xml xml
      end

      # @param yaml [String]
      # @return [Relaton::Oiml::ItemData]
      def from_yaml(yaml)
        require_relative "../oiml"
        Item.from_yaml(yaml)
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        require_relative "../oiml"
        @grammar_hash ||= ::Relaton::Oiml.grammar_hash
      end

      #
      # Remove index file
      #
      def remove_index_file
        require_relative "../oiml"
        Relaton::Index.find_or_create(:oiml, url: true, file: "#{INDEXFILE}.yaml").remove_file
      end
    end
  end
end
