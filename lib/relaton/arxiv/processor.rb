require_relative "../core/processor"

module Relaton
  module Arxiv
    class Processor < Relaton::Core::Processor
      attr_reader :idtype

      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_arxiv
        @prefix = "arXiv"
        @pubid_flavor = :Arxiv # prefixes and the Db cache key
        @defaultprefix = /^arXiv[:\s]/i
        @idtype = "arXiv"
        @datasets = %w[]
      end

      # @param code [String, Pubid::Arxiv::Identifier]
      # @param date [String, nil] year (ignored: the id carries it)
      # @param opts [Hash]
      # @return [Relaton::Bib::ItemData, nil]
      def get(code, date, opts)
        require_relative "../arxiv"
        ::Relaton::Arxiv::Bibliography.get(code, date, opts)
      end

      # `Pubid.parse` routes by a case-sensitive prefix; `Pubid::Arxiv.parse`
      # also reads `arxiv:…` and a bare id.
      def cache_pubid(ref)
        require "pubid"
        ::Pubid::Arxiv.parse ref.strip
      rescue ArgumentError, ::Pubid::Errors::Error
        require_relative "../bib"
        Relaton::Bib::Util.info "does not parse as an arXiv id; passing " \
                                "the reference to the flavor as written",
                                "relaton-db", key: ref
        nil
      end

      # An arXiv id carries its year and month, and they are identity: a
      # year option must not make a key for another month's paper.
      def fold_year(pubid, _year)
        pubid
      end

      # @param xml [String]
      # @return [Relaton::Bib::ItemData]
      def from_xml(xml)
        require_relative "../arxiv"
        ::Relaton::Bib::Bibitem.from_xml xml
      end

      # @param hash [Hash]
      # @return [Relaton::Bib::ItemData]
      def from_yaml(hash)
        require_relative "../arxiv"
        ::Relaton::Bib::Bibitem.from_hash hash
      end

      # @return [String]
      def grammar_hash
        require_relative "../arxiv"
        @grammar_hash ||= ::Relaton::Arxiv.grammar_hash
      end
    end
  end
end
