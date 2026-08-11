# frozen_string_literal: true

module Relaton
  module Itu
    # Hit.
    class Hit < Relaton::Core::Hit
      attr_writer :item

      # The document itself. An index-derived hit (`:file`) is loaded from the
      # data repository on demand — a reference matching many editions builds a
      # hit per edition, and only the one Bibliography selects is downloaded.
      # Everything else is scraped from www.itu.int.
      #
      # @return [Relaton::Itu::ItemData, nil]
      def item
        @item ||= if hit[:file] then hit_collection.fetch_item(hit[:url])
                  else Scraper.parse_page self, imp: gi_imp
                  end
      end

      private

      def gi_imp
        @gi_imp ||= /\.Imp\d/.match?(hit[:ref].to_s)
      end
    end
  end
end
