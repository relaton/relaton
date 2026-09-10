module Relaton
  module Plateau
    class Hit < Relaton::Core::Hit
      # The index names the file, so a non-200 is an access failure, not a
      # miss. Without the check the error page body reached Item.from_yaml,
      # which returned an item with no docidentifier.
      def item
        @item ||= begin
          uri = URI("#{HitCollection::ENDPOINT}#{hit[:file]}")
          resp = Net::HTTP.get_response(uri)
          unless resp.code == "200"
            raise Relaton::RequestError,
                  "Could not access #{uri}: HTTP #{resp.code}"
          end

          Item.from_yaml(resp.body)
        end
      end
    end
  end
end
