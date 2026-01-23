# frozen_string_literal: true

module Relaton::Bsi
  # Class methods for search ISO standards.
  class Bibliography
    class << self
      # @param text [String]
      # @return [Relaton::Bsi::HitCollection]
      def search(text, year = nil)
        code = text.sub(/^BSI\s/, "").sub(/ExComm|Expert commentary/, "Ex")
        HitCollection.search(code, year)
      rescue SocketError, Timeout::Error, Errno::EINVAL, Errno::ECONNRESET,
             EOFError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
             Net::ProtocolError, Algolia::AlgoliaUnreachableHostError => e
        raise Relaton::RequestError, e.message
      end

      #
      # @param code [String] the BSI standard Code to look up
      # @param year [String] the year the standard was published (optional)
      # @param opts [Hash] options
      # @option opts [Boolean] :all_parts if all-parts reference is required
      # @option opts [Boolean] :no_year if last published document is required
      #
      # @return [String] Relaton XML serialisation of reference
      def get(code, year = nil, opts = {})
        # y = code.split(":")[1]
        year ||= code_parts(code)[:year]
        ret = bib_get(code, year, opts)
        return nil if ret.nil?

        ret = ret.to_most_recent_reference unless year || opts[:keep_year]
        # ret = ret.to_all_parts if opts[:all_parts]
        ret
      end

      #
      # Destruct code to its parts.
      #
      # @param [String] code document identifier
      #
      # @return [MatchData] parts of the code
      #
      def code_parts(code)
        %r{
          ^(?:BSI\s)?(?<code>(?:[A-Z]+\s)*[^:\s+]+(?:\s\d+)?)
          (?::(?<year>\d{4})(?:-\d{2})?)?
          (?:\+(?<a>[^:\s]+)(?::(?<y>\d{4}))?)?
          (?:\s(?<rest>.+))?
        }x.match code
      end

      private

      def fetch_ref_err(code, year, missed_years) # rubocop:disable Metrics/MethodLength
        # y = code_parts(code)[:year]
        # id = year && !y ? "#{code}:#{year}" : code
        # Util.warn "WARNING: no match found online for `#{id}`. " \
        #           "The code must be exactly like it is on the standards website."
        unless missed_years.empty?
          Util.info "There was no match for `#{year}`, though there " \
                    "were matches found for `#{missed_years.join('`, `')}`."
        end
        # if /\d-\d/.match? code
        #   warn "[relaton-bsi] The provided document part may not exist, or "\
        #     "the document may no longer be published in parts."
        # else
        #   warn "[relaton-bsi] If you wanted to cite all document parts for "\
        #     "the reference, use \"#{code} (all parts)\".\nIf the document "\
        #     "is not a standard, use its document type abbreviation (TS, TR, "\
        #     "PAS, Guide)."
        # end
        nil
      end

      #
      # Search for a BSI standard.
      #
      # @param [String] code the BSI standard Code to look up
      #
      # @return [Relaton::Bsi::HitCollection] a collection of hits
      #
      def search_filter(code)
        cp = code_parts code
        Util.info "Fetching from shop.bsigroup.com ...", key: code
        unless cp
          Util.info "Could not parse the reference", key: code
          return []
        end

        search(code).filter_hits!(cp)
      end

      # Sort through the results from Isobib, fetching them three at a time,
      # and return the first result that matches the code,
      # matches the year (if provided), and which # has a title (amendments do not).
      # Only expects the first page of results to be populated.
      # Does not match corrigenda etc (e.g. ISO 3166-1:2006/Cor 1:2007)
      # If no match, returns any years which caused mismatch, for error reporting
      def results_filter(result, year)
        missed_years = []
        result.each do |r|
          pyear = code_parts(r.hit[:code])[:year]
          return { ret: r.item } if (!year || year == pyear) && r.item

          missed_years << pyear
        end
        { years: missed_years }
      end

      def bib_get(code, year, _opts)
        result = search_filter(code) || return
        ret = results_filter(result, year)
        if ret[:ret]
          Util.info "Found: `#{ret[:ret].docidentifier.first&.content}`", key: code
          ret[:ret]
        else
          Util.info "Not found", key: code
          fetch_ref_err(code, year, ret[:years])
        end
      end
    end
  end
end
