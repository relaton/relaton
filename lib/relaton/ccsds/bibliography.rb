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
      # @param ref [String, Pubid::Ccsds::Identifier] the reference, or
      #   the parse that Relaton::Db routed with (relaton#205)
      # @param year [String, nil]
      # @param opts [Hash]
      # @option opts [String] :format format of fetched document (DOC, PDF)
      #
      # @return [RelatonCcsds::BibliographicItem]
      #
      def get(ref, _year = nil, opts = {})
        query, opts = parse_format(ref, opts)
        Util.info "Fetching from Relaton repository ...", key: ref.to_s
        item, hit = fetch_item(query)
        if item.nil? || filter_sources(item, opts[:format])
          Util.info "Not found.", key: ref.to_s
          return nil
        end
        Util.info "Found: `#{hit[:code]}`.", key: ref.to_s
        item
      end

      private

      def parse_format(ref, opts)
        # A pubid carries no format suffix: Processor#query_pubid hands `get`
        # the String whenever the reference has one.
        return [ref, opts] unless ref.is_a?(String)

        query = ref.sub(/\s\((DOC|PDF)\)$/, "")
        opts[:format] ||= Regexp.last_match(1)
        [query, opts]
      end
      public :parse_format

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
