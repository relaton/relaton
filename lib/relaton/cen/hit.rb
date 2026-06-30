# frozen_string_literal: true

module Relaton
  module Cen
    # Hit.
    class Hit < Relaton::Core::Hit
      attr_writer :item

      # Parse page.
      # @return [IsoRelatonBib::IsoBibliographicItem]
      def item
        @fetch ||= Scraper.parse_page self
      end
    end
  end
end
