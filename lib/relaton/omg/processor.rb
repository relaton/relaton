require "relaton/core/processor"

module Relaton
  module Omg
    class Processor < Core::Processor
      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_omg
        @prefix = "OMG"
        @defaultprefix = /^OMG /
        @idtype = "OMG"
      end

      def get(code, date, opts)
        require_relative "../omg"
        Bibliography.get(code, date, opts)
      end

      def from_xml(xml)
        require_relative "../omg"
        Bibitem.from_xml xml
      end

      def from_yaml(yaml)
        require_relative "../omg"
        Item.from_yaml yaml
      end

      def grammar_hash
        require_relative "../omg"
        @grammar_hash ||= Omg.grammar_hash
      end
    end
  end
end
