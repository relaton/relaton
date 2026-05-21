# frozen_string_literal: true
require "relaton/core/processor"

module Relaton
  module Xsf
    class Processor < Relaton::Core::Processor
      attr_reader :idtype

      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_xsf
        @prefix = "XEP"
        @defaultprefix = %r{^XEP\s}
        @idtype = "XEP"
        @datasets = %w[xep-xmpp]
      end

      def get(code, date, opts)
        require_relative "../xsf"
        Relaton::Xsf::Bibliography.get(code, date, opts)
      end

      def fetch_data(_source, opts)
        require_relative "data_fetcher"
        Relaton::Xsf::DataFetcher.fetch(**opts)
      end

      def from_xml(xml)
        require_relative "../xsf"
        Relaton::Xsf::Item.from_xml(xml)
      end

      def from_yaml(yaml)
        require_relative "../xsf"
        Relaton::Xsf::Item.from_yaml(yaml)
      end

      def grammar_hash
        require_relative "../xsf"
        Relaton::Xsf.grammar_hash
      end

      def remove_index_file
        require_relative "../xsf"
        Relaton::Index.find_or_create(
          :xsf, url: true, file: "#{INDEXFILE}.yaml"
        ).remove_file
      end
    end
  end
end
