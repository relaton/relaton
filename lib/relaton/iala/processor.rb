require "relaton/core/processor"

module Relaton
  module Iala
    class Processor < Core::Processor
      attr_reader :idtype

      def initialize
        @short = :relaton_iala
        @prefix = "IALA"
        @defaultprefix = %r{^IALA\s}
        @idtype = "IALA"
      end

      def get(code, date, opts)
        require_relative "../iala"
        Bibliography.get(code, date, opts)
      end

      def from_xml(xml)
        require_relative "../iala"
        Item.from_xml xml
      end

      def from_yaml(yaml)
        require_relative "../iala"
        Item.from_yaml(yaml)
      end

      def grammar_hash
        require_relative "../iala"
        @grammar_hash ||= ::Relaton::Iala.grammar_hash
      end

      def remove_index_file
        require_relative "../iala"
        Relaton::Index.find_or_create(
          :iala, url: true, file: "#{INDEXFILE}.yaml",
          pubid_class: ::Pubid::Iala::Identifier
        ).remove_file
      end
    end
  end
end
