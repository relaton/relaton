# frozen_string_literal: true

module Relaton
  module Sdo
    # Singleton registry of organizations, built lazily from the index manifest
    # and memoized for the process. `reset!` drops the memo (mainly for specs).
    class Store
      include Singleton

      def initialize
        @mutex = Mutex.new
      end

      # Look up an organization by abbreviation (case-insensitive). Returns an
      # Organization or nil.
      def organization(abbreviation)
        index[normalize(abbreviation)]
      end

      # Lazily built and memoized; the mutex keeps a concurrent first access from
      # downloading/parsing the index twice.
      def index
        @index || @mutex.synchronize { @index ||= build_index }
      end

      def reset!
        @mutex.synchronize { @index = nil }
      end

      private

      def normalize(abbreviation)
        abbreviation.to_s.strip.upcase
      end

      def build_index
        yaml = Fetcher.fetch_index
        data = yaml.nil? || yaml.empty? ? {} : YAML.safe_load(yaml)
        # A corrupt/unexpected index (non-mapping YAML) degrades to "no orgs"
        # rather than crashing every lookup with a TypeError.
        organizations = data.is_a?(Hash) ? (data["organizations"] || {}) : {}
        organizations.each_with_object({}) do |(abbreviation, attrs), acc|
          acc[normalize(abbreviation)] =
            Organization.from_hash(abbreviation, attrs)
        end
      end
    end
  end
end
