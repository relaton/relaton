# frozen_string_literal: true

module Relaton
  module Cen
    # Class methods for search Cenelec standards.
    class Bibliography
      class << self
        # @param text [String]
        # @return [RelatonCen::HitCollection]
        def search(text, year = nil)
          # /^C?EN\s(?<code>.+)/ =~ text
          HitCollection.new(text, year).search
        rescue Mechanize::ResponseCodeError, Net::ReadTimeout => e
          raise Relaton::RequestError, e.message
        end

        #
        # @param code [String] the CEN standard Code to look up
        # @param year [String] the year the standard was published (optional)
        # @param opts [Hash] options
        # @option opts [Boolean] :keep_year don't upate reference
        #
        # @return [RelatonBib::BibliographicItem, nil]
        #
        def get(code, year = nil, opts = {})
          code_parts = code_to_parts code
          year ||= code_parts[:year] if code_parts

          bib_get(code, year, opts)
        end

        #
        # Decopmposes a CEN standard code into its parts.
        #
        # @param [String] code the CEN standard code to decompose
        #
        # @return [MatchData] the decomposition of the code
        #
        def code_to_parts(code)
          %r{^
            (?<code>[^:-]+)(?:-(?<part>\d+))?
            (?::(?<year>\d{4}))?
            (?:\+(?<amd>[A-Z]\d+)(?:(?<amy>\d{4}))?)?
            (?:\/(?<ac>AC\d+:\d{4}))?
          }x.match code
        end

        private

        def fetch_ref_err(code, year, missed_years) # rubocop:disable Metrics/MethodLength
          # id = year ? "#{code}:#{year}" : code
          # Util.warn "WARNING: No match found online for `#{id}`. " \
          #           "The code must be exactly like it is on the standards website."
          unless missed_years.empty?
            Util.info "There was no match for `#{year}`, though there " \
                      "were matches found for `#{missed_years.join('`, `')}`."
          end
          # if /\d-\d/.match? code
          #   warn "[relaton-cen] The provided document part may not exist, or "\
          #     "the document may no longer be published in parts."
          # else
          #   warn "[relaton-cen] If you wanted to cite all document parts for "\
          #     "the reference, use \"#{code} (all parts)\".\nIf the document "\
          #     "is not a standard, use its document type abbreviation (TS, TR, "]
          #     "PAS, Guide)."
          # end
          nil
        end

        # @param code [String]
        # @return [RelatonCen::HitCollection]
        def search_filter(code) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
          parts = code_to_parts code
          result = search(code)
          result.select! do |i|
            pts = code_to_parts i.hit[:code]
            parts[:code] == pts[:code] &&
              (!parts[:part] || parts[:part] == pts[:part]) &&
              (!parts[:year] || parts[:year] == pts[:year]) &&
              parts[:amd] == pts[:amd] && (!parts[:amy] || parts[:amy] == pts[:amy])
          end
        end

        # Sort through the results from Isobib, fetching them three at a time,
        # and return the first result that matches the code,
        # matches the year (if provided), and which # has a title (amendments do not).
        # Only expects the first page of results to be populated.
        # Does not match corrigenda etc (e.g. ISO 3166-1:2006/Cor 1:2007)
        # If no match, returns any years which caused mismatch, for error reporting
        def isobib_results_filter(result, year)
          missed_years = []
          result.each do |r|
            /:(?<pyear>\d{4})/ =~ r.hit[:code]
            if !year || year == pyear
              ret = r.item
              return { ret: ret } if ret
            end

            missed_years << pyear
          end
          { years: missed_years }
        end

        def bib_get(code, year, opts) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength
          ref = year.nil? || code.match?(/:\d{4}/) ? code : "#{code}:#{year}"
          Util.info "Fetching from standards.cencenelec.eu ...", key: ref
          result = search_filter(code) || return
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
