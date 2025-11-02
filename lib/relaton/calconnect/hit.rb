module Relaton::Calconnect
  class Hit < Relaton::Core::Hit
    # Parse page.
    # @return [Relaton::Calconnect::ItemData]
    def item
      # @fetch ||= Scraper.parse_page @hit
      @item ||= begin
        url = "#{HitCollection::GHURL}#{@hit[:file]}"
        resp = Faraday.get url
        Item.from_yaml resp.body
      end
    end
  end
end
