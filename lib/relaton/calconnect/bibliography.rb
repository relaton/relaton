require "mechanize"

module Relaton::Calconnect
  class Bibliography
    class << self
      # @param text [String]
      # @return [RelatonCalconnect::HitCollection]
      def search(text, year = nil, _opts = {})
        HitCollection.new text, year
      rescue Mechanize::ResponseCodeError, SocketError, Errno::ECONNREFUSED
        raise Relaton::RequestError, "Could not access https://standards.calconnect.org"
      end

      # @param ref [String] the OGC standard Code to look up (e..g "8200")
      # @param year [String] the year the standard was published (optional)
      #
      # @param opts [Hash] options
      # @option opts [TrueClass, FalseClass] :all_parts restricted to all parts
      #   if all-parts reference is required
      # @option opts [TrueClass, FalseClass] :bibdata
      #
      # @return [RelatonCalconnect::CcBibliographicItem]
      # The reference is no longer split by regex before searching. pubid parses
      # `CC/DIR 10005:2019` whole, so a dated reference narrows to that row in
      # the index itself; the `year` ARGUMENT is what still needs filtering
      # afterwards, because an undated reference reaches every year of the
      # document. That split is why `bib_results_filter` stays.
      def get(ref, year = nil, opts = {})
        Util.info "Fetching from Relaton repository ...", key: ref
        result = search(ref, year, opts) || (return nil)
        ret = bib_results_filter(result, year)
        if ret[:ret]
          Util.info "Found: `#{ret[:ret].docidentifier.first.content}`", key: ref
          ret[:ret]
        else
          Util.info "Not found.", key: ref
          fetch_ref_err(ref, year, ret[:years])
        end
      end

      private

      # Sort through the results from RelatonNist, fetching them three at a time,
      # and return the first result that matches the code,
      # matches the year (if provided), and which # has a title (amendments do not).
      # Only expects the first page of results to be populated.
      # Does not match corrigenda etc (e.g. ISO 3166-1:2006/Cor 1:2007)
      # If no match, returns any years which caused mismatch, for error reporting
      #
      # @param result
      # @param opts [Hash] options
      #
      # @return [Hash]
      def bib_results_filter(result, year)
        missed_years = Set.new
        result.each do |r|
          item = r.item
          item.fetched = Date.today.to_s
          return { ret: item } if !year

          # The row id is a `Pubid::Calconnect::Identifier` now, so the year is
          # read off the identifier rather than scraped from a rendered string.
          # The old `/:(\d{4})$/` regex would raise TypeError against it.
          id_year = r.hit[:id].date&.year
          return { ret: item } if year.to_i == id_year.to_i

          missed_years << id_year.to_i if id_year

          item.date.select { |d| d.type == "published" }.each do |d|
            return { ret: item } if year.to_i == d.at.to_date.year

            missed_years << d.at.to_date.year
          end
        end
        { years: missed_years }
      end

      # @param code [Strig]
      # @param year [String]
      # @param missed_years [Array<Strig>]
      def fetch_ref_err(code, year, missed_years)
        # id = year ? "`#{code}` year `#{year}`" : code
        # Util.info "WARNING: No match found online for #{id}. " \
        #           "The code must be exactly like it is on the standards website."
        unless missed_years.empty?
          Util.info "There was no match for `#{year}`, though there " \
                    "were matches found for `#{missed_years.join('`, `')}`."
        end
        nil
      end
    end
  end
end
