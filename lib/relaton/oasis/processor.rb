# frozen_string_literal: true

require "relaton/core/processor"

module Relaton
  module Oasis
    class Processor < Core::Processor
      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_oasis
        @prefix = "OASIS"
        @defaultprefix = %r{^OASIS\s}
        @idtype = "OASIS"
        @datasets = %w[oasis-open]
      end

      # @param code [String]
      # @param date [String, nil] year
      # @param opts [Hash]
      # @return [Relaton::Oasis::Item]
      def get(code, date, opts)
        require_relative "../oasis"
        Bibliography.get(code, date, opts)
      end

      #
      # Fetch all the documents from https://www.oasis-open.org/standards/
      #
      # @param [String] _source source name
      # @param [Hash] opts
      # @option opts [String] :output directory to output documents
      # @option opts [String] :format
      #
      def fetch_data(_source, opts)
        require_relative "data_fetcher"
        DataFetcher.fetch(**opts)
      end

      # @param xml [String]
      # @return [Relaton::Oasis::Item]
      def from_xml(xml)
        require_relative "../oasis"
        Item.from_xml(xml)
      end

      # @param yaml [String]
      # @return [Relaton::Oasis::Item]
      def from_yaml(yaml)
        require_relative "../oasis"
        Item.from_yaml(yaml)
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        require_relative "../oasis"
        @grammar_hash ||= Relaton::Oasis.grammar_hash
      end

      #
      # Remove index file
      #
      def remove_index_file
        require_relative "../oasis"
        Relaton::Index.find_or_create(:oasis, file: "#{INDEXFILE}.yaml").remove_file
      end
    end
  end
end
