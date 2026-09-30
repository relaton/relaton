require "mechanize"

module Relaton
  module Doi
    module Crossref
      extend self

      USER_AGENT = "Relaton::Doi (https://www.relaton.org/guides/doi/; mailto:open.source@ribose.com)"

      #
      # Get a document by DOI from the CrossRef API.
      #
      # @param [String, Pubid::Doi::Identifier] doi The DOI.
      #
      # @return [RelatonBib::BibliographicItem, RelatonIetf::IetfBibliographicItem,
      #   RelatonBipm::BipmBibliographicItem, RelatonIeee::IeeeBibliographicItem,
      #   RelatonNist::NistBibliographicItem] The bibitem.
      #
      def get(doi)
        key = doi.to_s
        Util.info "Fetching from search.crossref.org ...", key: key
        message = get_by_id doi_of(doi)
        if message
          Util.info "Found: `#{message['DOI']}`", key: key
          Parser.parse message
        else
          Util.info "Not found.", key: key
          nil
        end
      end

      #
      # The DOI itself (`<prefix>/<suffix>`), as the Crossref API takes it.
      #
      # A parsed pubid gives it from its components. A String may carry a
      # `doi:` scheme (in any case) or a `doi.org` URL: Relaton::Db keys every
      # form Pubid::Doi reads as one DOI, so all of them must reach the same
      # DOI here, or a miss on one form is cached for the others.
      #
      # @param [String, Pubid::Doi::Identifier] doi
      # @return [String]
      #
      def doi_of(doi)
        return "#{doi.prefix}/#{doi.suffix}" unless doi.is_a?(String)

        doi.sub(%r{\A(?:doi:|https?://(?:dx\.)?doi\.org/)}i, "")
      end

      #
      # Get a document by DOI from the CrossRef API.
      #
      # @param [String] id The DOI.
      #
      # @return [Hash] The document.
      #
      def get_by_id(id) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        n = 0
        url = "https://api.crossref.org/works/#{CGI.escape(id)}"
        loop do
          resp = agent.get url
          work = JSON.parse resp.body
          return work["message"] if work["status"] == "ok"

          if n > 1
            raise Relaton::RequestError, "Crossref error: #{resp.body}"
          end

          n += 1
          sleep backoff(resp.response, n)
        rescue Mechanize::ResponseCodeError => e
          return nil if e.response_code == "404"

          if n > 1
            raise Relaton::RequestError, "Crossref error: #{e.page.body}"
          end

          n += 1
          sleep backoff(e.page.response, n)
        end
      end

      #
      # Seconds to wait before retry n. Crossref sends X-Rate-Limit-Interval as
      # "1s", but a throttled response can carry no rate-limit headers at all —
      # the 429s seen here had only Date/Content-Length/Connection. Without the
      # floor that degenerates to `sleep 0`, i.e. hammering the endpoint that
      # just asked us to slow down.
      #
      # @param [Hash, nil] headers The response headers.
      # @param [Integer] num The attempt number.
      #
      # @return [Integer] Delay in seconds, at least 1.
      #
      def backoff(headers, num)
        interval = headers.to_h["x-rate-limit-interval"].to_s[/\d+/].to_i
        [interval, 1].max * num
      end

      def agent
        @agent ||= Mechanize.new do |a|
          a.user_agent = USER_AGENT
        end
      end
    end
  end
end
