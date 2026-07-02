require_relative "hit"

module Relaton
  module Ccsds
    class HitCollection < Relaton::Core::HitCollection
      GHURL = "https://raw.githubusercontent.com/relaton/relaton-data-ccsds/refs/heads/v2/".freeze

      #
      # Search his in index.
      #
      # @return [<Type>] <description>
      #
      def fetch
        @array = rows.map { |row| Hit.new code: row[:id], url: "#{GHURL}#{row[:file]}" }
        self
      rescue SocketError, OpenURI::HTTPError, OpenSSL::SSL::SSLError, Errno::ECONNRESET => e
        raise Relaton::RequestError, e.message
      end

      # Pubid index (index-v2): `:id` deserializes to a Pubid::Ccsds::Identifier
      # via pubid_class, so search narrows by number with binary search.
      def index
        @index ||= Relaton::Index.find_or_create(
          :ccsds, url: "#{GHURL}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml", pubid_class: Pubid::Ccsds::Identifier
        )
      end

      def pubid
        @pubid ||= Pubid::Ccsds::Identifier.parse(ref)
      end

      def rows
        if pubid.edition
          index.search(pubid)
        else
          # search(pubid) narrows candidates by number via binary search first.
          index.search(pubid) { |r| r[:id].exclude(:edition) == pubid }
        end
      end
    end
  end
end
