# frozen_string_literal: true

require "relaton/core/processor"

module Relaton
  module Jis
    class Processor < Relaton::Core::Processor
      attr_reader :idtype

      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_jis
        @prefix = "JIS"
        @defaultprefix = %r{^(JIS|TR)\s}
        @idtype = "JIS"
        @datasets = %w[jis-webdesk]
      end

      def get(code, date, opts)
        require_relative "../jis"
        Bibliography.get(code, date, opts)
      end

      def fetch_data(_source, opts)
        require_relative "data_fetcher"
        DataFetcher.fetch(**opts)
      end

      def from_xml(xml)
        require_relative "../jis"
        Item.from_xml xml
      end

      def from_yaml(yaml)
        require_relative "../jis"
        Item.from_yaml yaml
      end

      def grammar_hash
        require_relative "../jis"
        Digest::MD5.hexdigest Relaton::Jis::VERSION + Relaton::Bib::VERSION
      end

      def threads
        3
      end

      def remove_index_file
        require_relative "../jis"
        Relaton::Index.find_or_create(
          :jis, url: true, file: "#{INDEXFILE_V2}.yaml"
        ).remove_file
      end
    end
  end
end
