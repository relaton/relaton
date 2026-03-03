# frozen_string_literal: true

require_relative "../un"

module Relaton
  module Un
    class Processor < Core::Processor
      attr_reader :idtype

      def initialize
        @short = :relaton_un
        @prefix = "UN"
        @defaultprefix = %r{^UN\s}
        @idtype = "UN"
      end

      def get(code, date, opts)
        Bibliography.get(code, date, opts)
      end

      def from_xml(xml)
        Bibdata.from_xml(xml)
      end

      def from_yaml(yaml)
        Item.from_yaml(yaml)
      end

      def grammar_hash
        @grammar_hash ||= Relaton::Un.grammar_hash
      end
    end
  end
end
