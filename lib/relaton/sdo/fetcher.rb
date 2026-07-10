# frozen_string_literal: true

module Relaton
  module Sdo
    # Download helper. The index manifest is text-cached under the configured
    # storage dir with a TTL (reusing Relaton::Index::FileStorage); logo binaries
    # are fetched on demand and left to in-process memoization on the Logo.
    module Fetcher
      module_function

      # Fetch the index manifest, serving a fresh on-disk copy when present and
      # falling back to a stale cache if the network fetch fails.
      def fetch_index
        config = Sdo.configuration
        cache = File.join(config.storage_dir, "index.yaml")

        if fresh?(cache, config)
          cached = config.storage.read(cache)
          return cached if cached
        end

        data = download(config.url)
        return config.storage.read(cache) if data.nil? # stale cache or nil

        config.storage.write(cache, data)
        data
      end

      # GET a URL and return the body, or nil on failure. A URL with no scheme
      # (or a file:// URL) is read straight off disk — handy for local fixtures.
      def download(url)
        uri = url.is_a?(URI) ? url : URI.parse(url.to_s)
        return read_file(uri, url) if uri.scheme.nil? || uri.scheme == "file"

        response = Net::HTTP.get_response(uri)
        response.is_a?(Net::HTTPSuccess) ? response.body : nil
      rescue StandardError
        nil
      end

      def fresh?(file, config)
        ctime = config.storage.ctime(file)
        ctime && (Time.now - ctime) < config.ttl
      end

      def read_file(uri, url)
        path = uri.path.to_s.empty? ? url.to_s : uri.path
        File.exist?(path) ? File.binread(path) : nil
      end
    end
  end
end
