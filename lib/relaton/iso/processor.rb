require "relaton/core/processor"

module Relaton
  module Iso
    class Processor < Core::Processor
      attr_reader :idtype

      def initialize # rubocop:disable Lint/MissingSuper
        @short = :relaton_iso
        @prefix = "ISO"
        @defaultprefix = %r{^ISO(/IEC)?\s}
        @idtype = "ISO"
        @datasets = %w[iso-open-data iso-open-data-all]
      end

      # @param code [String]
      # @param date [String, nil] year
      # @param opts [Hash]
      # @return [RelatonIsoBib::IsoBibliographicItem]
      def get(code, date, opts)
        require_relative "../iso"
        Bibliography.get(code, date, opts)
      end

      #
      # Fetch all the documents from the ISO Open Data programme
      # (https://www.iso.org/open-data.html).
      #
      # @param [String] source source name
      #   * `iso-open-data` - skip if upstream `Last-Modified` is unchanged
      #   * `iso-open-data-all` - wipe `output` and re-emit every record
      # @param [Hash] opts
      # @option opts [String] :output directory to output documents
      # @option opts [String] :format output format (xml, yaml, bibxml)
      #
      def fetch_data(source, opts)
        require_relative "data_fetcher"
        DataFetcher.fetch(source, **opts)
      end

      # @param xml [String]
      # @return [RelatonIsoBib::IsoBibliographicItem]
      def from_xml(xml)
        require_relative "../iso"
        Item.from_xml xml
      end

      def from_yaml(yaml)
        require_relative "../iso"
        Item.from_yaml yaml
      end

      # @param hash [Hash]
      # @return [RelatonIsoBib::IsoBibliographicItem]
      # def hash_to_bib(hash)
      #   item_hash = HashConverter.hash_to_bib(hash)
      #   ::RelatonIsoBib::IsoBibliographicItem.new(**item_hash)
      # end

      # Returns hash of XML grammar
      # @return [String]
      def grammar_hash
        require_relative "../iso"
        Iso.grammar_hash
      end

      # Returns number of workers
      # @return [Integer]
      def threads = 3

      #
      # Remove index file
      #
      def remove_index_file
        # ../iso defines INDEXFILE and loads Index, both otherwise missing
        # when remove_index_file runs without iso.rb already loaded.
        require_relative "../iso"
        require_relative "hit_collection"
        Index.find_or_create(:iso, url: true, file: "#{INDEXFILE}.yaml")
          .remove_file
      end
    end
  end
end
