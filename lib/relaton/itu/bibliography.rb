# frozen_string_literal: true

module Relaton
  module Itu
    module Bibliography
      extend self

      # Supplements that print the date of the recommendation they amend
      # first, "ITU-T G.989.2 (2014) Amd. 1 (04/2016)": their edition is the
      # base's.
      AMENDING = [
        ::Pubid::Itu::Identifiers::Amendment, ::Pubid::Itu::Identifiers::Corrigendum,
        ::Pubid::Itu::Identifiers::Errata, ::Pubid::Itu::Identifiers::Addendum,
      ].freeze

      # Parts of a recommendation that print its date first when it has one,
      # "ITU-T Z.100 (06/2021) Annex F1", and their own date otherwise.
      ANNEXED = [
        ::Pubid::Itu::Identifiers::AnnexOfRecommendation,
        ::Pubid::Itu::Identifiers::AppendixOfRecommendation,
      ].freeze

      # @param refid [Pubid::Itu::Identifier, String] a document reference; a
      #   String that Pubid::Itu cannot parse raises Pubid::Errors::ParseError
      # @return [Relaton::Itu::HitCollection]
      def search(refid)
        if refid.is_a? String
          warn_incorrect_ref(refid)
          refid = ::Pubid::Itu.parse refid
        end
        HitCollection.new(refid).tap(&:search)
      end

      # @param ref [String, Pubid::Itu::Identifier] the ITU standard Code to
      #   look up, or its parse from Relaton::Db (relaton#205); #with_year
      #   copies, so the pubid is not changed
      # @param year [String] the year the standard was published (optional)
      # @param opts [Hash] options
      # @return [Relaton::Bib::ItemData, nil]
      def get(ref, year = nil, opts = {})
        if ref.is_a? String
          warn_incorrect_ref(ref)
          ref = ::Pubid::Itu.parse(ref)
        end
        refid = with_year ref, year

        ret = itubib_get1(refid)
        return nil if ret.nil?

        unless edition_year(refid) || opts[:keep_year]
          ret = ret.to_most_recent_reference
        end
        ret = ret.to_all_parts if opts[:all_parts]
        ret
      end

      # The year a reference selects its hits by. It is read the way a hit
      # code's first date is: for an amending supplement, it is the year of
      # the recommendation it amends. HitCollection uses it too.
      #
      # @param refid [Pubid::Itu::Identifier]
      # @return [String, nil]
      def edition_year(refid)
        return refid.base&.year if amending?(refid)
        return refid.base&.year || refid.year if annexed?(refid)

        refid.year
      end

      # The identifier a reference is a part of: the recommendation an
      # amending supplement, an annex or an appendix belongs to; else itself.
      # A series or recommendation supplement is a document of its own.
      #
      # @param refid [Pubid::Itu::Identifier]
      # @return [Pubid::Itu::Identifier]
      def document(refid)
        amending?(refid) || annexed?(refid) ? refid.base : refid
      end

      private

      # @param refid [Pubid::Itu::Identifier]
      # @param year [String, nil] the year passed beside the reference
      # @return [Pubid::Itu::Identifier] refid, dated with year when it has
      #   no year of its own
      def with_year(refid, year)
        return refid if year.nil? || edition_year(refid)

        hash = refid.to_hash
        dated = amending?(refid) ? hash["base"] : hash
        dated["year"] = year.to_s
        ::Pubid::Itu::Identifier.from_hash hash
      end

      def amending?(refid) = AMENDING.any? { |klass| refid.is_a? klass }

      def annexed?(refid) = ANNEXED.any? { |klass| refid.is_a? klass }

      def warn_incorrect_ref(ref)
        if ref =~ /(ITU[\s-]T\s\w)\.(Suppl\.|Annex)\s?(\w?\d+)/
          correct_ref = "#{$~[1]} #{$~[2]} #{$~[3]}"
          Util.info "Incorrect reference: `#{ref}`, the reference should be: `#{correct_ref}`"
        end
      end

      def fetch_ref_err(refid, missed_years)
        Util.info "Not found.", key: refid.to_s
        # one hit per edition means a year can repeat (a recommendation and its
        # amendment); the requested year itself is not a "different year" hint
        year = edition_year(refid)
        years = missed_years.uniq.reject { |y| y == year }
        if years.any?
          plural = years.size > 1 ? "s" : ""
          Util.info "There was no match for `#{year}` year, though there " \
                    "were matches found for `#{years.join('`, `')}` " \
                    "year#{plural}.", key: refid.to_s
        end
        nil
      end

      # Keep the hits that are the referenced document, in any edition:
      # #isobib_results_filter picks the year afterwards. The date is ignored,
      # and the version only when the reference names none. Everything else
      # must be equal, so a supplement, or a Report for a Recommendation, never
      # matches.
      #
      # Not `===`: it reads a missing `subseries` as "any value", so
      # `ITU-T H.264` would keep `ITU-T H.264.1`.
      def search_filter(refid)
        ignore = %i[year month day]
        ignore << :version unless stated_version?(refid)
        search(refid).select do |i|
          next true unless i.hit[:code]

          hit = ::Pubid::Itu.parse(i.hit[:code])
          refid.matches?(hit, ignore: ignore) && same_own_date?(refid, hit)
        rescue ::Pubid::Errors::ParseError
          false # a live hit ITU spells in a form nothing can identify
        end
      end

      # A version on the reference, or on the recommendation it amends.
      def stated_version?(refid)
        id = document(refid)
        id.respond_to?(:version) && !id.version.nil?
      end

      # `ignore:` drops the date at every level, but an amending supplement's
      # own date tells two "Amd. 1" to different editions apart.
      def same_own_date?(refid, hit)
        return true unless amending?(refid)

        own = refid.to_hash.slice("year", "month", "day")
        own.all? { |key, value| hit.to_hash[key] == value }
      end

      def isobib_results_filter(result, refid)
        missed_years = []
        year = edition_year(refid)
        result.each do |r|
          /\((?:\d{2}\/)?(?<pyear>\d{4})\)/ =~ r.hit[:code]
          if !year || year == pyear
            ret = r.item
            return { ret: ret } if ret
          end

          # a hit whose code carries no year contributes nothing to the
          # "matches found for `<year>`" hint
          missed_years << pyear if pyear
        end
        { years: missed_years }
      end

      def itubib_get1(refid)
        result = search_filter(refid) || return
        ret = isobib_results_filter(result, refid)
        if ret[:ret]
          Util.info "Found: `#{ret[:ret].docidentifier.first&.content}`", key: refid.to_s
          ret[:ret]
        else
          fetch_ref_err(refid, ret[:years])
        end
      end
    end
  end
end
