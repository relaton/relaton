module Relaton
  module Ogc
    module Bibliography
      extend self

      # @param ref [String, Pubid::Ogc::Identifier]
      # @param year [String, nil]
      # @return [Relaton::Ogc::HitCollection]
      def search(ref, year = nil, _opts = {})
        code = ref.is_a?(String) ? ref.sub(/^OGC\s/, "") : ref
        HitCollection.new(code, year).find
      rescue Faraday::ConnectionFailed, Faraday::SSLError
        raise Relaton::RequestError, HitCollection::ENDPOINT
      end

      # @param ref [String, Pubid::Ogc::Identifier] a reference, or its parse
      #   from Relaton::Db (relaton#205), which is used as it is
      # @param year [String, nil]
      # @param opts [Hash]
      # @return [Relaton::Ogc::ItemData, nil]
      def get(ref, year = nil, opts = {})
        result = bib_search_filter(ref, year, opts) || (return nil)
        ret = bib_results_filter(result, year)
        if ret[:ret]
          Util.info "Found: `#{ret[:ret].docidentifier.first.content}`", key: ref.to_s
          ret[:ret]
        else
          fetch_ref_err(ref, year, ret[:years])
        end
      end

      private

      def bib_search_filter(ref, year, opts)
        Util.info "Fetching from Relaton repository ...", key: ref.to_s
        search(ref, year, opts)
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

      def fetch_ref_err(ref, year, missed_years)
        Util.info "Not found.", key: ref.to_s
        unless missed_years.empty?
          Util.info "There was no match for `#{year}`, though there " \
                    "were matches found for `#{missed_years.join('`, `')}`.", key: ref.to_s
        end
        nil
      end
    end
  end
end
