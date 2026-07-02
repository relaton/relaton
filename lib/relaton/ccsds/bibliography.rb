require_relative "hit_collection"

module Relaton
  module Ccsds
    module Bibliography
      extend self

      #
      # Search for CCSDS standards by document reference.
      #
      # @param [String] ref document reference
      #
      # @return [RelatonCcsds::HitCollection] collection of hits
      #
      def search(ref)
        HitCollection.new(ref).fetch
      end

      #
      # Get CCSDS standard by document reference.
      # If format is not specified, then all format will be returned.
      #
      # @param reference [String]
      # @param year [String, nil]
      # @param opts [Hash]
      # @option opts [String] :format format of fetched document (DOC, PDF)
      #
      # @return [RelatonCcsds::BibliographicItem]
      #
      def get(reference, _year = nil, opts = {})
        ref, opts = parse_format(reference, opts)
        Util.info "Fetching from Relaton repository ...", key: reference
        item, hit = fetch_item(ref)
        if item.nil? || filter_sources(item, opts[:format])
          Util.info "Not found.", key: reference
          return nil
        end
        Util.info "Found: `#{hit[:code]}`.", key: reference
        item
      end

      private

      def parse_format(reference, opts)
        ref = reference.sub(/\s\((DOC|PDF)\)$/, "")
        opts[:format] ||= Regexp.last_match(1)
        [ref, opts]
      end

      def fetch_item(ref)
        hit = search(ref).first
        [hit&.item, hit&.hit]
      end

      def filter_sources(item, format)
        return unless format

        item.source = item.source.select { |s| s.type == format.downcase }
        item.source.empty?
      end
    end
  end
end
