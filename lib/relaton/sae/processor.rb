require_relative "../core/processor"

module Relaton
  module Sae
    class Processor < Relaton::Core::Processor
      attr_reader :idtype

      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_sae
        @prefix = "SAE"
        @defaultprefix = /^SAE\s/
        @idtype = "SAE"
        @datasets = %w[sae-crossref]
        # Db cache key: `Pubid::Sae` reads the reference and SAE's native
        # edition code (`SAE J3016_202104`) alike.
        @pubid_flavor = :Sae
      end

      # @param code [String, Pubid::Sae::Identifier]
      # @param date [String, nil] year
      # @param opts [Hash]
      # @return [Relaton::Sae::ItemData, nil]
      def get(code, date, opts)
        require_relative "../sae"
        Bibliography.get(code, date, opts)
      end

      # @param source [String] `sae-crossref`
      # @param opts [Hash] `output:`, `format:`
      def fetch_data(source, opts)
        require_relative "data_fetcher"
        DataFetcher.fetch(source, **opts)
      end

      # @param xml [String]
      # @return [Relaton::Sae::ItemData]
      def from_xml(xml)
        require_relative "../sae"
        Item.from_xml xml
      end

      # @param yaml [String]
      # @return [Relaton::Sae::ItemData]
      def from_yaml(yaml)
        require_relative "../sae"
        Item.from_yaml yaml
      end

      # @return [String]
      def grammar_hash
        require_relative "../sae"
        @grammar_hash ||= Sae.grammar_hash
      end

      def remove_index_file
        require_relative "../sae"
        Relaton::Index.find_or_create(:sae, url: true,
                                            file: "#{INDEXFILE}.yaml").remove_file
      end
    end
  end
end
