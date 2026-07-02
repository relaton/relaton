# frozen_string_literal: true

module Relaton
  module Itu
    # Hit.
    class Hit < Relaton::Core::Hit
      attr_writer :item

      # Parse page.
      # @return [Relaton::Itu::ItemData]
      def item
        @item ||= Scraper.parse_page self, imp: gi_imp
      end

      private

      def gi_imp
        @gi_imp ||= /\.Imp\d/.match?(hit[:ref].to_s)
      end
    end
  end
end
