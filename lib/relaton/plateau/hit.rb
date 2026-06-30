module Relaton
  module Plateau
    class Hit < Relaton::Core::Hit
      def item
        @item ||= begin
          url = "#{HitCollection::ENDPOINT}#{hit[:file]}"
          resp = Net::HTTP.get_response(URI(url))
          Item.from_yaml(resp.body)
        end
      end
    end
  end
end
