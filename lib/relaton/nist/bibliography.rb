module Relaton
  module Nist
    class Bibliography
      extend Core::DateParser

      class << self
        #
        # Search NIST documents by reference
        #
        # @param ref [String] reference
        #
        # @return [Relaton::Nist::HitCollection] search result
        #
        def search(ref, year = nil, opts = {})
          query = ref.sub(/^NISTIR/, "NIST IR").sub(/\/Add/, " Add")
          # pubid 2.x only recognizes the addendum marker with a trailing
          # period, and only splits an uppercase part letter — canonicalize
          # both ("800-38a Add" -> "800-38A Add.") so @reference parses to the
          # same pubid the index/CSRC carry.
          query = query.sub(/\bAdd\b\.?/i, "Add.").sub(/([0-9])([a-z])(?=\s+Add\.)/) { "#{$1}#{$2.upcase}" }
          HitCollection.search query, year, opts
        rescue OpenURI::HTTPError, SocketError, OpenSSL::SSL::SSLError => e
          raise Relaton::RequestError, e.message
        end

        #
        # Get NIST document by reference
        #
        # @param ref [String, Pubid::Nist::Identifier] the NIST standard Code
        #   to look up, or its parse from Relaton::Db (relaton#205)
        # @param year [String] the year the standard was published (optional)
        # @param opts [Hash] options
        # @option opts [Boolean] :all_parts restricted to all parts
        #
        # @return [Relaton::Nist::ItemData, nil] bibliographic item
        #
        def get(ref, year = nil, opts = {}) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
          # The lookup below works on text, so a pubid from Relaton::Db is
          # read back as its printed form; the pubid itself is not changed.
          ref = ref.to_s unless ref.is_a?(String)
          return fetch_ref_err(ref, year, []) if ref.match?(/\sEP$/)

          /^(?<code2>[^(]+)(?:\((?<date2>\w+\s(?:\d{2},\s)?\d{4})\))?\s?\(?(?:(?<=\()(?<stage>(?:I|F|\d)PD))?/ =~ ref
          stage ||= /(?<=\.)PD-\w+(?=\.)/.match(ref)&.to_s
          if code2
            ref = code2.strip
            opts[:date] = parse_date(date2, str: false) if date2
            opts[:stage] = stage if stage
          end

          if year.nil?
            /^(?<code1>[^:]+):(?<year1>[^:]+)$/ =~ ref
            unless code1.nil?
              ref = code1
              year = year1
            end
          end

          ref += "-1" if opts[:all_parts]
          nistbib_get(ref, year, opts)
        end

        private

        #
        # Get NIST document by reference
        #
        # @param [String] ref reference
        # @param [String] year year
        # @param [Hash] opts options
        #
        # @return [Relaton::Nist::ItemData, nil] bibliographic item
        #
        def nistbib_get(ref, year, opts)
          result = nistbib_search_filter(ref, year, opts) || (return nil)
          ret = nistbib_results_filter(result, year, opts)
          if ret[:ret]
            Util.info "Found: `#{ret[:ret].docidentifier.first.content}`", key: result.reference
            ret[:ret]
          else
            fetch_ref_err(result.reference, year, ret[:years])
          end
        end

        #
        # Sort through results, return first match by code, year, and title
        #
        # @param opts [Hash] options
        # @option opts [Date] :date date filter
        # @option opts [String] :stage stage filter
        #
        # @return [Hash] result
        #
        def nistbib_results_filter(result, year, opts)
          missed_years = []
          iteration = parse_iteration(opts[:stage])

          # A stageless query means "the published document". Multiple
          # editions can match once stage is excluded (e.g. a final "r2"
          # and its draft "Rev. 2 ipd"), so try published hits before
          # drafts. An explicit stage keeps the original order. Stable
          # partition preserves existing tie-order among finals.
          ordered = if iteration
                      result.array
                    else
                      result.array.sort_by.with_index { |h, i| [draft_hit?(h) ? 1 : 0, i] }
                    end

          ordered.each do |h|
            r = h.item
            next if opts[:date] && !match_date?(r, opts[:date])
            next if iteration && r.status&.iteration != iteration
            return { ret: r } unless year
            next unless match_year?(r, year) { |y| missed_years << y }

            return { ret: r }
          end
          { years: missed_years }
        end

        # A hit is a draft when its CSRC status says so (e.g. "draft-public")
        # or its rendered code carries a PD stage marker (ipd/fpd/NpD).
        def draft_hit?(hit)
          hit.hit[:status].to_s.include?("draft") ||
            hit.hit[:code].to_s.match?(/(?:\bi|\bf|\b\d)pd\b|\(Draft\)/i)
        end

        def parse_iteration(stage)
          iter = /\w+(?=PD)|(?<=PD-)\w+/.match(stage)&.to_s
          case iter
          when "I" then "1"
          when "F" then "final"
          else iter
          end
        end

        def match_date?(item, date)
          item.date.any? do |d|
            date_val = d.at || d.from
            date_val && parse_date(date_val.to_s, str: false) == date
          end
        end

        def match_year?(item, year)
          item.date.select { |d| d.type == "published" || d.type == "issued" }.each do |d|
            date_val = d.at || d.from
            next unless date_val

            parsed_year = parse_date(date_val.to_s, str: false)&.year
            return parsed_year if year.to_i == parsed_year

            yield parsed_year if block_given?
          end
          nil
        end

        #
        # Get search results and filter them by code and year
        #
        # @param ref [String] reference
        # @param year [String, nil] year
        # @param opts [Hash] options
        #
        # @return [Relaton::Nist::HitCollection] hits collection
        #
        def nistbib_search_filter(ref, year, opts)
          result = search(ref, year, opts)
          result.search_filter
        end

        #
        # Outputs warning message if no match found
        #
        # @param [String] ref reference
        # @param [String, nil] year year
        # @param [Array<String>] missed_years missed years
        #
        # @return [nil] nil
        #
        def fetch_ref_err(ref, year, missed_years)
          Util.info "Not found.", key: ref
          unless missed_years.empty?
            Util.info "(There was no match for #{year}, though there " \
                      "were matches found for `#{missed_years.join('`, `')}`.)", key: ref
          end
          if /\d-\d/.match? ref
            Util.info "The provided document part may not exist, " \
                      "or the document may no longer be published in parts.", key: ref
          end
          nil
        end
      end
    end
  end
end
