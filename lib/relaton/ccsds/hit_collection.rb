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
          # `exact:` keeps the match exact. `Type#search` without it takes
          # pubid's subset match `pubid === row`. pubid declares `language`
          # `subset_strict`, so a translation no longer matches, but `suffix` is
          # still a wildcard: `CCSDS 101.0-B-4` would also reach the historical
          # `CCSDS 101.0-B-4-S` (260 such pairs in the index fixture).
          index.search(pubid, exact: true)
        else
          # search(pubid) narrows candidates by number via binary search first.
          index.search(pubid) { |r| r[:id].exclude(:edition) == pubid }
        end
      end
    end
  end
end
