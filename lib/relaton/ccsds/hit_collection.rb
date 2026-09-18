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
          # The block keeps the match **exact**. `Type#search` without one takes
          # pubid's subset match, where the language a CCSDS reference omits is
          # a wildcard, so the reference would also reach its translations (345
          # such pairs in the index fixture).
          index.search(pubid) { |r| r[:id] == pubid }
        else
          # search(pubid) narrows candidates by number via binary search first.
          index.search(pubid) { |r| r[:id].exclude(:edition) == pubid }
        end
      end
    end
  end
end
