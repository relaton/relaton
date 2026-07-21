# frozen_string_literal: true

module Relaton::Bsi
  # Class methods for search ISO standards.
  class Bibliography
    # pubid identifier types referenced when navigating the parsed object graph.
    Ids = ::Pubid::Bsi::Identifiers

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
        year ||= publication_year(code)
        ret = bib_get(code, year, opts)
        return nil if ret.nil?

        ret = ret.to_most_recent_reference unless year || opts[:keep_year]
        ret
      end

      # Parse a BSI reference with pubid; nil when pubid can't parse it.
      # @param [String] code document identifier
      # @return [Pubid::Bsi::Identifier, nil]
      def parse(code)
        ::Pubid::Bsi::Identifier.parse(code)
      rescue StandardError
        nil
      end

      # Publication year of a reference's base document.
      # @param [String] code document identifier
      # @return [String, nil]
      def publication_year(code)
        parse(code)&.base_document&.year&.to_s
      end

      # Whether a query and a candidate hit denote the same BSI document, at the
      # fuzziness the hit filter asks for. Built entirely on pubid: `base_document`
      # peels supplements/wrappers, `matches?` compares ignoring the publication
      # date, and the uniform `Amendment`/`Corrigendum` `#supplement_*` interface
      # supplies the amendment number/year.
      #
      # @param query [Pubid::Bsi::Identifier]
      # @param hit   [Pubid::Bsi::Identifier]
      # @param skip_rest [Boolean] ignore the free-text suffix (ExComm / Flex version)
      # @param drop_amd  [Boolean] reduce the hit to its base document before
      #   matching, so a query for the base document matches a catalogue entry
      #   that only exists in amended form (the returned id is de-amended too)
      # @return [Boolean]
      def same_reference?(query, hit, skip_rest: false, drop_amd: false)
        hit = hit.base_document if drop_amd

        base_match?(query, hit) &&
          same_supplement?(supplement_of(query), supplement_of(hit)) &&
          (skip_rest || rest_marker(query) == rest_marker(hit))
      end

      private

      # Same base document, ignoring the publication date. `:month` is excluded
      # alongside `:date` because Flex identifiers store the month separately, so
      # `exclude(:date)` alone leaves them unequal.
      def base_match?(query, hit)
        query.base_document.matches?(hit.base_document, ignore: %i[date month])
      end

      # The `Amendment`/`Corrigendum` supplement of a reference, if any — peeling
      # an Expert-commentary wrapper first. Both supplements expose the uniform
      # `#supplement_type` / `#supplement_number` / `#supplement_year`.
      def supplement_of(id)
        while id.is_a?(Ids::ExpertCommentary)
          inner = id.base
          break if inner.nil? || inner.equal?(id)

          id = inner
        end
        return nil unless id.respond_to?(:identifiers) && id.identifiers

        id.identifiers.find { |i| i.respond_to?(:supplement_type) }
      end

      # Same supplement, with the amendment year treated as optional when the
      # query omits it (a query for "…+A2" matches a hit for "…+A2:2020").
      def same_supplement?(query_supp, hit_supp)
        return hit_supp.nil? if query_supp.nil?
        return false if hit_supp.nil?

        query_supp.supplement_type == hit_supp.supplement_type &&
          query_supp.supplement_number == hit_supp.supplement_number &&
          (query_supp.supplement_year.nil? ||
            query_supp.supplement_year == hit_supp.supplement_year)
      end

      # Canonical marker for the free-text suffix pubid parses into a typed
      # wrapper (so an `ExComm` query matches an `Expert Commentary` hit).
      def rest_marker(id)
        return :expert_commentary if id.is_a?(Ids::ExpertCommentary)
        return :"flex_#{id.edition}" if id.is_a?(Ids::Flex) && id.edition

        nil
      end

      def fetch_ref_err(_code, year, missed_years)
        unless missed_years.empty?
          Util.info "There was no match for `#{year}`, though there " \
                    "were matches found for `#{missed_years.join('`, `')}`."
        end
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
        query = parse(code)
        Util.info "Fetching from shop.bsigroup.com ...", key: code
        unless query
          Util.info "Could not parse the reference", key: code
          return []
        end

        search(code).filter_hits!(query)
      end

      # Sort through the results, and return the first result that matches the
      # code and matches the year (if provided), and which has a title.
      # If no match, returns any years which caused mismatch, for error reporting.
      def results_filter(result, year)
        missed_years = []
        result.each do |r|
          pyear = publication_year(r.hit[:code])
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
