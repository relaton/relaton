require "relaton/core"
require_relative "../w3c"

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
        Bibliography.get(code, date, opts)
      end

      def fetch_data(_source, opts)
        require_relative "data_fetcher"
        DataFetcher.fetch(**opts)
      end

      def from_xml(xml)
        Item.from_xml(xml)
      end

      def from_yaml(yaml)
        Item.from_yaml(yaml)
      end

      def grammar_hash
        @grammar_hash ||= Relaton::W3c.grammar_hash
      end

      def remove_index_file
        Relaton::Index.find_or_create(
          :W3C, url: true, file: "#{INDEXFILE}.yaml"
        ).remove_file
      end
    end
  end
end
