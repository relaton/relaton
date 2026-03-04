module Relaton
  module W3c
    module RateLimitHandler
      MAX_RETRIES = 5
      RETRYABLE_ERRORS = [
        NameError, Lutaml::Hal::ConnectionError, Lutaml::Hal::TimeoutError,
        Faraday::ConnectionFailed, Net::OpenTimeout,
      ].freeze

      def self.fetched_objects
        @fetched_objects ||= {}
      end

      def realize(obj)
        href = resolve_href(obj)
        return RateLimitHandler.fetched_objects[href] if RateLimitHandler.fetched_objects.key?(href)

        attempt = 1
        begin
          RateLimitHandler.fetched_objects[href] = obj.realize
        rescue *RETRYABLE_ERRORS => e
          if attempt < MAX_RETRIES
            sleep_time = attempt * attempt
            attempt += 1
            Util.warn "Rate limit exceeded for #{href}, retrying in #{sleep_time} seconds..."
            sleep sleep_time
            retry
          else
            # Do not cache on retries exhausted — transient failures should not
            # permanently poison the cache; subsequent calls will retry fresh.
            Util.warn "Failed to realize object: #{href}, error: #{e.message}"
          end
        rescue Lutaml::Hal::NotFoundError
          Util.warn "Object not found: #{href}"
          RateLimitHandler.fetched_objects[href] = nil
        rescue Lutaml::Hal::ServerError => e
          Util.warn "Server error while realizing object: #{href}, error: #{e.message}"
          RateLimitHandler.fetched_objects[href] = nil
        end
      end

      private

      def resolve_href(obj)
        obj.href || obj.links.self.href
      end
    end
  end
end
