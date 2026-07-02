require "relaton/core/processor"

module Relaton
  module Bipm
    class Processor < Relaton::Core::Processor
      attr_reader :idtype

      def initialize
        @short = :relaton_bipm
        @prefix = "BIPM"
        @defaultprefix = %r{^(?:BIPM|CCTF|CCDS|CGPM|CIPM|JCRB|JCGM)(?!\w)}
        @idtype = "BIPM"
        @datasets = %w[bipm-data-outcomes bipm-si-brochure rawdata-bipm-metrologia]
      end

      # @param code [String]
      # @param date [String, NilClass] year
      # @param opts [Hash]
      # @return [RelatonBipm::BipmBibliographicItem]
      def get(code, date, opts)
        require_relative "../bipm"
        Bibliography.get(code, date, opts)
      end

      #
      # Fetch all the documents from https://github.com/metanorma/bipm-data-outcomes,
      #   https://github.com/metanorma/bipm-si-brochure, https://github.com/relaton/rawdata-bipm-metrologia
      #
      # @param [String] source source name (bipm-data-outcomes, bipm-si-brochure,
      #   rawdata-bipm-metrologia)
      # @param [Hash] opts
      # @option opts [String] :output directory to output documents
      # @option opts [String] :format
      #
      def fetch_data(source, opts)
        require_relative "data_fetcher"
        DataFetcher.fetch(source, **opts)
      end

      # @param xml [String]
      # @return [RelatonBipm::BipmBibliographicItem]
      def from_xml(xml)
        require_relative "../bipm"
        Item.from_xml xml
      end

      def from_yaml(yaml)
        require_relative "../bipm"
        Item.from_yaml yaml
      end


      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        require_relative "../bipm"
        @grammar_hash ||= Relaton::Bipm.grammar_hash
      end

      #
      # Remove index file
      #
      def remove_index_file
        require_relative "../bipm"
        Relaton::Index.find_or_create(:bipm, url: true, file: INDEXFILE).remove_file
      end
    end
  end
end
