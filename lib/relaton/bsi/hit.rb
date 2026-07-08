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

    # The hit's reference parsed with pubid, memoized so the (up to three) hit
    # filter passes don't re-parse it. `nil` when pubid can't parse the code.
    # @return [Pubid::Bsi::Identifier, nil]
    def pubid
      return @pubid if defined?(@pubid)

      @pubid = Bibliography.parse(hit[:code])
    end
  end
end
