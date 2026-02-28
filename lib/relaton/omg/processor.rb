require "relaton/core/processor"
require_relative "../omg"

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
        Bibliography.get(code, date, opts)
      end

      def from_xml(xml)
        Bibitem.from_xml xml
      end

      def from_yaml(yaml)
        Item.from_yaml yaml
      end

      def grammar_hash
        @grammar_hash ||= Omg.grammar_hash
      end
    end
  end
end
