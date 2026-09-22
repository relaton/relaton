# frozen_string_literal: true

module Relaton
  module Cen
    # Class methods for search Cenelec standards.
    class Bibliography
      class << self
        # @param text [String]
        # @return [Relaton::Cen::HitCollection]
        def search(text, year = nil)
          HitCollection.new(text, year).search
        rescue Mechanize::ResponseCodeError, Net::ReadTimeout => e
          raise Relaton::RequestError, e.message
        end

        #
        # Parses a printed CEN/CENELEC reference.
        #
        # Deliberately does NOT rescue. An unrecognized query reference must
        # raise, so that relaton-cli can print `"…" is not a recognized
        # standards identifier`; returning nil would make "malformed" look like
        # "not found". Only the DATA side rescues — see `Hit#pubid`, which
        # drops a catalogue code the grammar cannot read (`prEN 13306 rev`).
        #
        # @param ref [String] a printed reference, e.g. "EN 285:2015+A1"
        #
        # @return [Pubid::CenCenelec::Identifier]
        # @raise [Pubid::Errors::ParseError]
        #
        def parse(ref)
          ::Pubid::CenCenelec::Identifier.parse ref
        end

        #
        # @param code [String] the CEN standard Code to look up
        # @param year [String] the year the standard was published (optional)
        # @param opts [Hash] options
        # @option opts [Boolean] :keep_year don't upate reference
        #
        # @return [Relaton::Cen::ItemData, nil]
        #
        def get(code, year = nil, opts = {})
          # An empty string is no reference, not a malformed one, so it stays a
          # plain nil rather than a parse failure. Mirrors the guard
          # HitCollection#search already carries.
          return if code.nil? || code.strip.empty?

          query = parse code
          year ||= publication_year query

          bib_get code, year, opts, query
        end

        private

        #
        # The year of the document the reference names: the base document's
        # year for a supplement, and the adopted document's year for an adopted
        # norm (an `AdoptedEuropeanNorm` carries no year of its own, so `#root`
        # is the accessor that answers for every form).
        #
        # @param id [Pubid::CenCenelec::Identifier]
        #
        # @return [String, nil]
        #
        def publication_year(id)
          id.root.year&.to_s
        end

        # A component is absent from a reference when excluding it changes
        # nothing. This replaces the old capture-group tests, and works for the
        # forms that hold the component on a nested identifier (an adopted norm
        # keeps its part on the adopted ISO document).
        #
        # @return [Boolean]
        def absent?(id, *keys)
          id.exclude(*keys) == id
        end

        def fetch_ref_err(_code, year, missed_years)
          unless missed_years.empty?
            Util.info "There was no match for `#{year}`, though there " \
                      "were matches found for `#{missed_years.join('`, `')}`."
          end
          nil
        end

        #
        # Selects the portal hits that denote the same document as the query.
        #
        # The search text stays the caller's raw reference — that is
        # search-engine input, not identifier parsing — while the SELECTION is
        # pubid's. A hit whose code the grammar cannot read is dropped rather
        # than aborting the search.
        #
        # The selection is pubid's subset match `query === hit.pubid`. A part,
        # a year or a supplement year that the query omits matches any value.
        # pubid declares the CEN `type`, `stage` and `typed_stage` strict, so
        # `EN 1325` matches neither `prEN 1325` nor `CEN/TS 1325`. The class
        # must be identical, so a base reference never answers with its own
        # amendment's record, and a supplement reference never answers with
        # its base document.
        #
        # @param code [String] the raw reference, as the portal form wants it
        # @param query [Pubid::CenCenelec::Identifier]
        #
        # @return [Relaton::Cen::HitCollection]
        #
        def search_filter(code, query)
          search(code).select! { |hit| hit.pubid && query === hit.pubid }
        end

        # Sort through the results from Isobib, fetching them three at a time,
        # and return the first result that matches the code,
        # matches the year (if provided), and which # has a title (amendments do not).
        # Only expects the first page of results to be populated.
        # If no match, returns any years which caused mismatch, for error reporting
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

        def bib_get(code, year, opts, query) # rubocop:disable Metrics/MethodLength
          ref = year && absent?(query, :year) ? "#{code}:#{year}" : code
          Util.info "Fetching from standards.cencenelec.eu ...", key: ref
          result = search_filter(code, query)
          ret = isobib_results_filter(result, year)
          if ret[:ret]
            bib = year || opts[:keep_year] ? ret[:ret] : ret[:ret].to_most_recent_reference
            Util.info "Found: `#{bib.docidentifier.first&.content}`", key: ref
            bib
          else
            Util.info "Not found.", key: ref
            fetch_ref_err(code, year, ret[:years])
          end
        end
      end
    end
  end
end
