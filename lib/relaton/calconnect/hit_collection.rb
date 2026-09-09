module Relaton::Calconnect
  class HitCollection < Relaton::Core::HitCollection
    GHURL = "https://raw.githubusercontent.com/relaton/relaton-data-calconnect/refs/heads/v2/".freeze

    # @param ref [Strig]
    # @param year [String]
    def initialize(ref, year = nil)
      super
      @array = search_index(ref).map { |row| Hit.new(row, self) }
    end

    private

    # @return [Relaton::Index::Type]
    def index
      Relaton::Index.find_or_create :CC, url: "#{GHURL}#{INDEXFILE}.zip",
                                         file: "#{INDEXFILE}.yaml",
                                         pubid_class: ::Pubid::Calconnect::Identifier
    end

    #
    # The index rows matching a reference, most recent first.
    #
    # **The pubid is passed to `Index::Type#search`, not the string.**
    # `search_candidates` narrows only when the argument is not a `String`, and
    # a block alone never narrows — so the plain string this used to pass
    # disabled the binary search however the index was built. `pubid_class:` on
    # the index alone fixes nothing; both had to change together.
    #
    # This also ends the substring scan the old string search did, which was
    # silently ambiguous: `CC/DIR 1000` answered with all five `CC/DIR 1000x`
    # documents and `CC/A 1` with every `CC/A 1xxx`. A number now matches
    # exactly, and a leading zero is significant (`CC/A 0001` is not `CC/A 1`).
    #
    # @param ref [String]
    # @return [Array<Hash>] matching index rows
    #
    def search_index(ref)
      pubid = parse_ref ref
      return [] unless pubid

      rows = index.search(pubid) do |row|
        pubid.matches? row[:id], ignore: ignored(pubid)
      end
      rows.sort_by { |row| [recency_key(row[:id]), row[:file]] }
    end

    #
    # Parse a user reference into a `Pubid::Calconnect::Identifier`, or nil.
    #
    # A reference pubid rejects is a **miss, not an error**: this returns nil
    # outside the transport rescue in `Bibliography.search`, so it never becomes
    # a `Relaton::RequestError`.
    #
    # @param ref [String]
    # @return [Pubid::Calconnect::Identifier, nil]
    #
    # An unrecognized reference **raises**; like ISO, ETSI and 3GPP we let it
    # propagate. relaton-cli rescues `Parslet::ParseFailed` and renders
    # `"..." is not a recognized standards identifier`
    # (`gems/relaton-cli/lib/relaton/cli/command.rb:324`), and `Db#fetch`
    # logs it through the `StandardError` arm at `lib/relaton/db.rb:122`.
    # Rescuing here would collapse "this identifier is malformed" into "no
    # such document", leaving a caller unable to tell them apart.
    def parse_ref(ref)
      ::Pubid::Calconnect::Identifier.parse ref.to_s.strip
    end

    #
    # The components the reference left out, which a row may carry freely.
    #
    # The date is the only one: CalConnect's other components are the
    # identifier's own identity. `series` in particular is never ignorable — it
    # is what keeps `CC/CD 51016` and `CC/WD 51016` apart — and neither is the
    # absence of a series, so `CC 36010` does not match `CC/WD 36010`.
    #
    # @param pubid [Pubid::Calconnect::Identifier]
    # @return [Array<Symbol>]
    #
    def ignored(pubid)
      pubid.date.nil? ? %i[year] : []
    end

    #
    # Sort key placing the most recent document first.
    #
    # The index is sorted by number, so rows sharing a number arrive in no
    # meaningful order — without this, `Bibliography.get "CC/S 0601"` would
    # answer with an arbitrary one of the 2005 and 2006 documents. Segments are
    # compared as integers and negated for descending order; an absent month or
    # day sorts as 0, which is right because only one row in the corpus carries
    # either.
    #
    # @param id [Pubid::Calconnect::Identifier]
    # @return [Array<Integer>]
    #
    def recency_key(id)
      date = id.date
      return [0, 0, 0] unless date

      [date.year, date.month, date.day].map { |part| -part.to_i }
    end
  end
end
