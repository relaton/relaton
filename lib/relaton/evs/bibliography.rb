# frozen_string_literal: true

module Relaton
  module Evs
    # Class methods for search Estonian standards.
    class Bibliography
      class << self
        # @param ref [String] the printed reference
        # @return [Relaton::Evs::HitCollection]
        def search(ref, year = nil)
          HitCollection.new(ref, year).search
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          raise Relaton::RequestError, e.message
        end

        #
        # Parses a printed EVS reference.
        #
        # Deliberately does NOT rescue. An unrecognized query reference must
        # raise, so that relaton-cli can print `"…" is not a recognized
        # standards identifier`; returning nil would make "malformed" look
        # like "not found". Only the DATA side rescues — see `Hit#pubid`.
        #
        # @param ref [String] a printed reference, e.g. "EVS-EN 18216:2026"
        #
        # @return [Pubid::Evs::Identifier]
        # @raise [Pubid::Errors::ParseError]
        #
        def parse(ref)
          ::Pubid::Evs.parse ref
        end

        #
        # @param ref [String, Pubid::Evs::Identifier] the EVS standard
        #   reference to look up, or its parse from Relaton::Db (relaton#205)
        # @param year [String] the year the standard was published (optional)
        # @param opts [Hash] options
        # @option opts [Boolean] :keep_year don't update reference
        #
        # @return [Relaton::Evs::ItemData, nil]
        #
        def get(ref, year = nil, opts = {})
          # An empty string is no reference, not a malformed one, so it stays a
          # plain nil rather than a parse failure. Mirrors the guard
          # HitCollection#search already carries.
          return if ref.nil? || (ref.is_a?(String) && ref.strip.empty?)

          # `Relaton::Db` hands `get` the parse it routed and keyed the cache
          # with; it must reach `bib_get` unmutated.
          query = ref.is_a?(String) ? parse(ref) : ref
          year ||= publication_year query

          bib_get ref.to_s, year, opts, query
        end

        private

        #
        # `#root` is the accessor that answers for every form: a national
        # adoption keeps the origin standard's number and year behind its
        # `base` chain, and a direct adoption or plain Estonian standard is
        # its own root.
        #
        # @param id [Pubid::Evs::Identifier]
        #
        # @return [String, nil]
        #
        def publication_year(id)
          id.root.year&.to_s
        end

        # A component is absent from a reference when excluding it changes
        # nothing.
        #
        # @return [Boolean]
        def absent?(id, *keys)
          id.exclude(*keys) == id
        end

        def fetch_ref_err(ref, year, missed_years)
          unless missed_years.empty?
            Util.info "There was no match for `#{year}`, though there " \
                      "were matches found for `#{missed_years.join('`, `')}`.",
                      key: ref
          end
          nil
        end

        #
        # Selects the catalogue hits that denote the same document as the
        # query. The selection is pubid's subset match `query === hit.pubid`:
        # a year the query omits matches any value, and the class must be
        # identical, so a base reference never answers with its own
        # amendment's record.
        #
        # @param ref [String] the printed reference, as the catalogue URL
        #   wants it
        # @param query [Pubid::Evs::Identifier]
        #
        # @return [Relaton::Evs::HitCollection]
        #
        def search_filter(ref, query)
          search(ref).select! { |hit| hit.pubid && query === hit.pubid }
        end

        # Fetch the matching hit, keeping the year filter for error reporting.
        def isobib_results_filter(result, year)
          missed_years = []
          result.each do |r|
            pyear = r.pubid && publication_year(r.pubid)
            if !year || year == pyear
              ret = r.item
              return { ret: ret } if ret
            end

            missed_years << pyear
          end
          { years: missed_years }
        end

        def bib_get(ref, year, opts, query)
          key = year && absent?(query, :year) ? "#{ref}:#{year}" : ref
          Util.info "Fetching from www.evs.ee ...", key: key
          result = search_filter(ref, query)
          ret = isobib_results_filter(result, year)
          if ret[:ret]
            bib = year || opts[:keep_year] ? ret[:ret] : ret[:ret].to_most_recent_reference
            Util.info "Found: `#{bib.docidentifier.first&.content}`", key: key
            bib
          else
            Util.info "Not found.", key: key
            fetch_ref_err(ref, year, ret[:years])
          end
        end
      end
    end
  end
end
