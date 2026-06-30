# frozen_string_literal: true

module Relaton::Bsi
  # Hit.
  class Hit < Relaton::Core::Hit
    attr_writer :fetch

    # Parse page.
    # @return [Relaton::Bsi::ItemData]
    def item
      @item ||= Scraper.parse_page self
    end
  end
end
