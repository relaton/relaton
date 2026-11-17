require_relative "../core/processor"

module Relaton
  module Iho
    class Processor < Core::Processor
      def cache_key(ref, year, opts, parsed = nil)
        super
      end
      attr_reader :idtype

      def initialize
        @short = :relaton_iho
        @prefix = "IHO"
        @pubid_identifier = :Iho # Db cache key
        @defaultprefix = %r{^IHO\s}
        @idtype = "IHO"
      end

      # @param code [String]
      # @param date [String, nil] year
      # @param opts [Hash]
      # @return [Relaton::Iho::ItemData, nil]
      def get(code, date, opts)
        require_relative "../iho"
        Bibliography.get(code, date, opts)
      end

      # The long section form with an edition qualifier ("S-4 Part B,
      # Section 400, Edition 4.9.0", relaton#531) is read by the flavor,
      # not by pubid's grammar, so the Db cache key comes from the same
      # parse `get` uses.
      def cache_pubid(ref)
        require_relative "../iho"
        Bibliography.parse_reference(ref)
      rescue ArgumentError, ::Pubid::Errors::Error
        super
      end

      # An IHO record prints `B-12` and keeps its edition in `edition`, so
      # the edition goes on the key (relaton#408). The component model
      # (relaton#440) renamed the pubid attribute `version` -> `edition`.
      def item_cache_key(pubid, item)
        with_components pubid, edition: item.edition&.content
      end

      # @param xml [String]
      # @return [Relaton::Iho::ItemData]
      def from_xml(xml)
        require_relative "../iho"
        Item.from_xml xml
      end

      # @param yaml [String]
      # @return [Relaton::Iho::ItemData]
      def from_yaml(yaml)
        require_relative "../iho"
        Item.from_yaml(yaml)
      end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        require_relative "../iho"
        @grammar_hash ||= ::Relaton::Iho.grammar_hash
      end

      #
      # Remove index file
      #
      def remove_index_file
        require_relative "../iho"
        Relaton::Index.find_or_create(:iho, url: true, file: "#{INDEXFILE}.yaml").remove_file
      end
    end
  end
end
