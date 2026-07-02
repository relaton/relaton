require "relaton/core/processor"

module Relaton
  module Plateau
    class Processor < Relaton::Core::Processor
      attr_reader :idtype

      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_plateau
        @prefix = "PLATEAU"
        @defaultprefix = /^PLATEAU\s/
        @idtype = "PLATEAU"
        @datasets = %w[plateau-handbooks plateau-technical-reports]
      end

      def get(code, date, opts)
        require_relative "../plateau"
        Bibliography.get(code, date, opts)
      end

      def fetch_data(source, opts)
        require_relative "data_fetcher"
        DataFetcher.fetch(source, **opts)
      end

      def from_xml(xml)
        require_relative "../plateau"
        Item.from_xml xml
      end

      def from_yaml(yaml)
        require_relative "../plateau"
        Item.from_yaml yaml
      end

      def grammar_hash
        require_relative "../plateau"
        @grammar_hash ||= ::Relaton::Plateau.grammar_hash
      end

      def threads = 3

      def remove_index_file
        require_relative "../plateau"
        Relaton::Index.find_or_create(:plateau, url: true, file: "#{INDEXFILE}.yaml").remove_file
      end
    end
  end
end
