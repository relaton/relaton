require "mechanize"

module Relaton
  module Doi
    module Crossref
      extend self

      USER_AGENT = "Relaton::Doi (https://www.relaton.org/guides/doi/; mailto:open.source@ribose.com)"

      #
      # Get a document by DOI from the CrossRef API.
      #
      # @param [String] doi The DOI.
      #
      # @return [RelatonBib::BibliographicItem, RelatonIetf::IetfBibliographicItem,
      #   RelatonBipm::BipmBibliographicItem, RelatonIeee::IeeeBibliographicItem,
      #   RelatonNist::NistBibliographicItem] The bibitem.
      #
      def get(doi)
        Util.info "Fetching from search.crossref.org ...", key: doi
        id = doi.sub(%r{^doi:}, "")
        message = get_by_id id
        if message
          Util.info "Found: `#{message['DOI']}`", key: doi
          Parser.parse message
        else
          Util.info "Not found.", key: doi
          nil
        end
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
