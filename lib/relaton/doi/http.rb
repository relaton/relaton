require "cgi"
require "mechanize"
require "openssl"
require "yeptris"

module Relaton
  module Doi
    #
    # JSON GET for the DOI services other than the Crossref works API:
    # doi.org's registration agency lookup and the DataCite REST API.
    #
    # A 404 answers nil. Any other failure retries twice, then raises
    # Relaton::RequestError, so that Relaton::Db retries it and never caches a
    # transport failure as "not found" (see docs/doi.md, "Rate limiting").
    #
    module Http
      extend self

      MAX_RETRIES = 2

      # A transport failure: the service did not give a readable answer.
      # A non-JSON 200 (a proxy's or a CDN's error page) is one too.
      NETWORK_ERRORS = [
        SocketError, Timeout::Error, SystemCallError, IOError, # IOError covers EOFError
        OpenSSL::SSL::SSLError, Net::HTTP::Persistent::Error,
        Mechanize::ResponseReadError, Mechanize::RedirectLimitReachedError,
        Mechanize::RedirectNotGetOrHeadError, ::Yeptris::JSON::ParseError
      ].freeze

      MAX_RETRY_DELAY = 60

      #
      # @param [String] url
      # @param [String] service the service name for the error message
      #
      # @return [Hash, Array, nil] the parsed body, or nil on a 404
      #
      def get_json(url, service) # rubocop:disable Metrics/MethodLength
        attempt = 0
        begin
          Relaton::Json.parse_external agent.get(url).body
        rescue Mechanize::ResponseCodeError => e
          return nil if e.response_code == "404"

          attempt += 1
          fail_after_retries attempt, service, e.page.body
          sleep backoff(e.page.response, attempt)
          retry
        rescue *NETWORK_ERRORS => e
          attempt += 1
          fail_after_retries attempt, service, e.message
          sleep backoff({}, attempt)
          retry
        end
      end

      #
      # Seconds to wait before retry `num`: the numeric `Retry-After` when the
      # service sends one, else 1 second, times the attempt, at most
      # MAX_RETRY_DELAY. A missing header never means "retry at once".
      #
      # @param [Hash, nil] headers
      # @param [Integer] num
      #
      # @return [Integer]
      #
      def backoff(headers, num)
        after = headers.to_h["retry-after"].to_s
        seconds = after.match?(/\A\d+\z/) ? after.to_i : 1
        [[seconds, 1].max * num, MAX_RETRY_DELAY].min
      end

      def agent
        @agent ||= Mechanize.new { |a| a.user_agent = Crossref::USER_AGENT }
      end

      private

      def fail_after_retries(attempt, service, detail)
        return if attempt <= MAX_RETRIES

        raise Relaton::RequestError, "#{service} error: #{detail}"
      end
    end
  end
end
