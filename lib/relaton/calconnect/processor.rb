require "relaton/core/processor"

module Relaton::Calconnect
  class Processor < Relaton::Core::Processor
    attr_reader :idtype

    def initialize # rubocop:disable Lint/MissingSuper
      @short = :relaton_calconnect
      @prefix = "CC"
      @defaultprefix = %r{^CC(?!\w)}
      @idtype = "CC"
      @datasets = %w[calconnect-org]
    end

    # @param code [String]
    # @param date [String, nil] year
    # @param opts [Hash]
    # @return [Relaton::Calconnect::ItemData, nil]
    def get(code, date, opts)
      require_relative "../calconnect"
      Bibliography.get(code, date, opts)
    end

    #
    # Fetch all the documents from a source
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
    # @return [Relaton::Calconnect::ItemData]
    def from_xml(xml)
      require_relative "../calconnect"
      Item.from_xml xml
    end

    # @param hash [Hash]
    # @return [Relaton::Calconnect::ItemData]
    def hash_to_bib(hash)
      require_relative "../calconnect"
      Item.from_yaml hash.to_yaml
    end

    # Returns hash of XML grammar
    # @return [String]
    def grammar_hash
      require_relative "../calconnect"
      @grammar_hash ||= ::Relaton::Calconnect.grammar_hash
    end

    #
    # Remove index file
    #
    def remove_index_file
      require_relative "../calconnect"
      Relaton::Index.find_or_create(:CC, url: true, file: "#{INDEXFILE}.yaml").remove_file
    end
  end
end
