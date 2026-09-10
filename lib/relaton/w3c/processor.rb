require "relaton/core/processor"

module Relaton
  module W3c
    class Processor < Relaton::Core::Processor
      attr_reader :idtype

      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_w3c
        @prefix = "W3C"
        @defaultprefix = %r{^W3C\s}
        @idtype = "W3C"
        @datasets = %w[w3c-api]
      end

      def get(code, date, opts)
        require_relative "../w3c"
        Bibliography.get(code, date, opts)
      end

      def fetch_data(_source, opts)
        require_relative "data_fetcher"
        DataFetcher.fetch(**opts)
      end

      def from_xml(xml)
        require_relative "../w3c"
        Item.from_xml(xml)
      end

      def from_yaml(yaml)
        require_relative "../w3c"
        Item.from_yaml(yaml)
      end

      def grammar_hash
        require_relative "../w3c"
        @grammar_hash ||= Relaton::W3c.grammar_hash
      end

      def remove_index_file
        require_relative "../w3c"
        Relaton::Index.find_or_create(
          :W3C, url: true, file: "#{INDEXFILE}.yaml"
        ).remove_file
      end
    end
  end
end
