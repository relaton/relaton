module Relaton
  module Itu
    # An ITU document identifier, backed by `Pubid::Itu`.
    #
    # `content` stays the source string for serialization. `#pubid` parses it
    # into a `Pubid::Itu::Identifier`, and `#remove_date!` changes that pubid
    # and renders it back into `content`. There is no string surgery.
    #
    # ## Why the parse is lazy
    #
    # Most ITU records also carry an `ISO` co-identifier ("ISO/IEC 14496-10"),
    # which never parses with `Pubid::Itu`. An eager parse in `content=` would
    # run a failed Parslet parse on every deserialization. So `#pubid` parses on
    # first use and keeps the result until `content` changes.
    #
    # The parse is soft: content that does not parse gives a nil `#pubid`, with
    # no log, because an ISO co-identifier is not a defect. With a nil `#pubid`
    # the mutators do nothing.
    class Docidentifier < Bib::Docidentifier
      # Capture the inherited content setter before the override, so that a
      # mutation can write the rendered string back and keep the changed pubid.
      # `content=` would clear it, and a new parse would lose nothing here, but
      # it would parse again for no reason.
      alias_method :store_content, :content=

      def content=(value)
        super
        @pubid = nil
        @pubid_parsed = false
      end

      # @return [Pubid::Itu::Identifier, nil] nil if the content does not parse
      def pubid
        return @pubid if @pubid_parsed

        @pubid_parsed = true
        @pubid = parse
      end

      # Removes the year and the month from the identifier and from every
      # identifier in its `base` chain, because `Pubid::Identifier#exclude`
      # recurses into `base`:
      #
      #   ITU-T L.163 (11/2018)               -> ITU-T L.163
      #   ITU-T H.264 (2005) Amd. 1 (06/2006) -> ITU-T H.264 Amd. 1
      #
      # The version stays: `ITU-T H.264 (V14) (08/2021)` -> `ITU-T H.264 (V14)`.
      # It is not a date, and two versions are two documents.
      #
      # The result is the pubid canonical spelling, so a source `v10` becomes
      # `(V10)`. `Pubid::Itu` has no `year=`/`month=` setters, so `#exclude` is
      # the only way to clear them.
      #
      # `remove_part!` and `to_all_parts!` stay the inherited no-ops: the `-3`
      # of `ITU-R P.838-3` is a revision, not a part.
      def remove_date!
        return unless pubid

        @pubid = @pubid.exclude(:year, :month)
        store_content @pubid.to_s
      end

      private

      def parse
        return unless content

        require "pubid"
        ::Pubid::Itu.parse content.to_s
      rescue LoadError, StandardError
        nil
      end
    end
  end
end
