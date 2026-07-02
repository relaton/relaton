require "relaton/core/processor"

module Relaton
  module Etsi
    class Processor < Relaton::Core::Processor
      attr_reader :idtype

      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_etsi
        @prefix = "ETSI"
        @defaultprefix = %r{^ETSI\s}
        @idtype = "ETSI"
        @datasets = %w[etsi-csv]
      end

      # @param code [String]
      # @param date [String, nil] year
      # @param opts [Hash]
      # @return [Relaton::Etsi::Item]
      def get(code, date, opts)
        require_relative "../etsi"
        Bibliography.get(code, date, opts)
      end

      #
      # Fetch all the documents from https://www.etsi.org
      #
      # @param [String] _source source name
      # @param [Hash] opts
      # @option opts [String] :output directory to output documents
      # @option opts [String] :format output format (xml, yaml, bibxml)
      #
      def fetch_data(_source, opts)
        require_relative "data_fetcher"
        DataFetcher.fetch(**opts)
      end

      # @param xml [String]
      # @return [Relaton::Etsi::Item]
      def from_xml(xml)
        require_relative "../etsi"
        Item.from_xml xml
      end

      # @param yaml [String]
      # @return [Relaton::Etsi::Item]
      def from_yaml(yaml)
        require_relative "../etsi"
        Item.from_yaml yaml
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        require "digest/md5" # not loaded by etsi.rb; needed on the cold path
        require "relaton/bib/version"
        require_relative "version"
        Digest::MD5.hexdigest Relaton::Etsi::VERSION + Relaton::Bib::VERSION
      end

      #
      # Remove index file
      #
      def remove_index_file
        require_relative "../etsi"
        Relaton::Index.find_or_create(:etsi, url: true, file: INDEX_FILE).remove_file
      end
    end
  end
end
