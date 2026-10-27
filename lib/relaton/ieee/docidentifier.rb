module Relaton
  module Ieee
    # IEEE document identifier. An `IEEE` docid is backed by a
    # Pubid::Ieee::Identifier so `remove_date!` can strip the year when an
    # undated reference answers with its latest edition (relaton-ieee#29).
    # ISBN and DOI docids carry no pubid and are never changed.
    class Docidentifier < Bib::Docidentifier
      # Strip the year: `IEEE Std 528-2019` -> `IEEE Std 528`, and the
      # trademark docid `IEEE Std 528™-2019` -> `IEEE Std 528™`. An id with no
      # year is left as it is: a re-render would change its spelling
      # (`IEEE P802.5t™/D-2.5` -> `IEEE P802.5t®/D2.5`).
      def remove_date!
        pubid = parse_pubid
        return unless pubid&.year

        undated = pubid.exclude(:year)
        self.content = scope == "trademark" ? undated.to_s(trademark: true) : undated.to_s
      end

      # IEEE has no all-parts form: both are no-ops, so
      # `Bib::ItemData#to_all_parts` never raises.
      def remove_part!; end

      def to_all_parts!; end

      private

      def parse_pubid
        return unless type == "IEEE" && content

        ::Pubid::Ieee::Identifier.parse content
      rescue StandardError
        nil
      end
    end
  end
end
