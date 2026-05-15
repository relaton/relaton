require "mechanize"

module Relaton::Calconnect
  class Hit < Relaton::Core::Hit
    # Parse page.
    # @return [Relaton::Calconnect::ItemData]
    def item
      @item ||= begin
        url = "#{HitCollection::GHURL}#{@hit[:file]}"
        Item.from_yaml Mechanize.new.get(url).body
      end
    end
  end
end
