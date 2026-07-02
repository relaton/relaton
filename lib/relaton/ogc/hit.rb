module Relaton
  module Ogc
    class Hit < Core::Hit
      # @return [Relaton::Ogc::ItemData]
      def item
        @item ||= begin
          url = "#{HitCollection::ENDPOINT}#{hit[:file]}"
          resp = Faraday.get(url) { |req| req.options.timeout = 10 }
          return unless resp.status == 200

          item = Item.from_yaml resp.body
          item.fetched = Date.today.to_s
          item
        end
      end
    end
  end
end
