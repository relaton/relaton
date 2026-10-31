require "relaton/core/processor"

module Relaton
  module Nist
    class Processor < Core::Processor
      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_nist
        @prefix = "NIST"
        @pubid_flavor = :Nist # global prefixes sourced from Pubid::Nist.prefixes
        @defaultprefix = %r{^(NIST|NBS|NISTGCR|ITL Bulletin|JPCRD|NISTIR|CSRC|FIPS)(/[^\s])?\s}
        @idtype = "NIST"
        @datasets = %w[nist-tech-pubs]
      end

      # @param code [String]
      # @param date [String, NilClass] year
      # @param opts [Hash]
      # @return [Relaton::Nist::ItemData]
      def get(code, date = nil, opts = {})
        require_relative "../nist"
        Bibliography.get(code, date, opts)
      end

      # Two kinds of Cswp table reference reach `get` as written and are not
      # cached (relaton#406). A legacy dated id answers the numbered record
      # with the dated id added, and Db would store that record under the
      # numbered id's row, so a later "NIST CSWP 9" would carry the dated id.
      # A translation that pubid reads in another form ("NIST CSWP
      # 04162018ar" as "...04162018a", "NIST CSWP 6 spa" as "...6(spa)").
      #
      # @param ref [String]
      # @return [Pubid::Nist::Identifier, nil]
      def cache_pubid(ref)
        pubid = super
        return if pubid.nil?

        require_relative "cswp"
        type, = Cswp.lookup(ref)
        return pubid if type.nil? || (type == :translation && pubid.to_s == ref)

        nil
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
      # @return [Relaton::Nist::ItemData]
      def from_xml(xml)
        require_relative "../nist"
        Item.from_xml(xml)
      end

      # @param yaml [String]
      # @return [Relaton::Nist::ItemData]
      def from_yaml(yaml)
        require_relative "../nist"
        Item.from_yaml(yaml)
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        require_relative "../nist"
        @grammar_hash ||= Nist.grammar_hash
      end

      #
      # Remove index file
      #
      def remove_index_file
        require_relative "../nist"
        Relaton::Index.find_or_create(
          :nist, url: true, file: "#{INDEXFILE}.yaml"
        ).remove_file
      end
    end
  end
end
