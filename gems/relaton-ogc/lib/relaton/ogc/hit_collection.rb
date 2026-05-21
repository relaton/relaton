require "faraday"
require_relative "hit"

module Relaton
  module Ogc
    class HitCollection < Core::HitCollection
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-ogc/v2/".freeze

      # @return [self]
      def find
        return self if ref.nil? || ref.empty?

        row = index.search(ref).min_by { |r| r[:id] }
        return self unless row

        url = "#{ENDPOINT}#{row[:file]}"
        resp = Faraday.get(url) { |req| req.options.timeout = 10 }
        return self unless resp.status == 200

        item = Item.from_yaml resp.body
        item.fetched = Date.today.to_s
        hit = Hit.new({ code: item.docidentifier[0]&.content, file: row[:file] }, self)
        hit.instance_variable_set(:@item, item)
        @array = [hit]
        self
      end

      # @return [Relaton::Index]
      def index
        @index ||= Relaton::Index.find_or_create(
          :ogc, url: "#{ENDPOINT}index-v1.zip", file: "#{INDEXFILE}.yaml",
        )
      end
    end
  end
end
