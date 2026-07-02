module Relaton
  module Ogc
    module Bibliography
      extend self

      # @param text [String]
      # @param year [String, nil]
      # @return [Relaton::Ogc::HitCollection]
      def search(text, year = nil, _opts = {})
        code = text.sub(/^OGC\s/, "")
        HitCollection.new(code, year).find
      rescue Faraday::ConnectionFailed, Faraday::SSLError
        raise Relaton::RequestError, HitCollection::ENDPOINT
      end

      # @param code [String]
      # @param year [String, nil]
      # @param opts [Hash]
      # @return [Relaton::Ogc::ItemData, nil]
      def get(code, year = nil, opts = {})
        result = bib_search_filter(code, year, opts) || (return nil)
        ret = bib_results_filter(result, year)
        if ret[:ret]
          Util.info "Found: `#{ret[:ret].docidentifier.first.content}`", key: code
          ret[:ret]
        else
          fetch_ref_err(code, year, ret[:years])
        end
      end

      private

      def bib_search_filter(code, year, opts)
        Util.info "Fetching from Relaton repository ...", key: code
        search(code, year, opts)
      end

      def bib_results_filter(result, year)
        missed_years = []
        result.each do |r|
          item = r.item
          return { ret: item } unless year

          item.date.select { |d| d.type == "published" }.each do |d|
            date_year = ::Date.parse(d.at.to_s).year
            return { ret: item } if year.to_i == date_year

            missed_years << date_year
          end
        end
        { years: missed_years }
      end

      def fetch_ref_err(code, year, missed_years)
        Util.info "Not found.", key: code
        unless missed_years.empty?
          Util.info "There was no match for `#{year}`, though there " \
                    "were matches found for `#{missed_years.join('`, `')}`.", key: code
        end
        nil
      end
    end
  end
end
