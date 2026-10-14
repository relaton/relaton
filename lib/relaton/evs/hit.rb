# frozen_string_literal: true

module Relaton
  module Evs
    # Hit.
    class Hit < Relaton::Core::Hit
      attr_writer :item

      # Parse page.
      # @return [Relaton::Evs::ItemData]
      def item
        @fetch ||= Scraper.parse_page self
      end

      # The hit's code parsed with pubid, memoized because the filter, the
      # sort and the scraper all read it. `nil` when pubid cannot parse the
      # code: the catalogue also hosts documents outside the EVS grammar
      # (a bare `EN` or `ISO` record linked as a base document), and one such
      # row must not abort the search. (A malformed *query* raises; see
      # `Bibliography.parse`.)
      #
      # @return [Pubid::Evs::Identifier, nil]
      def pubid
        return @pubid if defined?(@pubid)

        @pubid = Bibliography.parse hit[:code]
      rescue StandardError
        @pubid = nil
      end
    end
  end
end
