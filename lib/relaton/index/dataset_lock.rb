# frozen_string_literal: true

require "yeptris"

require "digest"
require "net/http"
require "time"
require "uri"
require "lutaml/model"

module Relaton
  module Index
    # A pinned dataset: the machine-index manifest's content address written to
    # a file, so a build can reproduce the exact index it consumed years later.
    #
    # The manifest (docs/data-repository-format.adoc) carries the SHA-256 and
    # size of the published whole-index zip. Capture records them; #verify
    # re-checks the bytes a consumer fetched.
    #
    #   lock = Relaton::Index::DatasetLock.capture(
    #     "https://relaton.github.io/relaton-data-iso/",
    #   )
    #   File.write(".relaton-lock.yaml", lock.to_yaml)
    #
    #   lock = Relaton::Index::DatasetLock.from_yaml(File.read(".relaton-lock.yaml"))
    #   lock.verify(File.binread(zip_path))
    class DatasetLock < Lutaml::Model::Serializable
      attribute :version, :integer
      attribute :pages_url, :string
      attribute :index, :string
      attribute :count, :integer
      attribute :shards, :integer
      attribute :generated, :string
      attribute :sha256, :string
      attribute :bytes, :integer
      attribute :captured_at, :string

      SHA256_HEX = /\A\h{64}\z/

      # The manifest names the artifact; these fields pin it. A manifest
      # published before content addressing has no sha256 and cannot be
      # locked: refusing is the point, a lock without a hash guarantees
      # nothing.
      def self.from_manifest(pages_url, manifest, captured_at: Time.now.utc.iso8601)
        unless manifest.is_a?(Hash)
          raise Error, "manifest is not a JSON object: #{manifest.class}"
        end

        sha = manifest["sha256"]
        unless sha.is_a?(String) && SHA256_HEX.match?(sha)
          raise Error,
                "manifest for #{pages_url} carries no sha256 content address; " \
                "republish the index with a generator that emits one"
        end

        index = manifest["index"]
        unless index.is_a?(String) && !index.empty?
          raise Error, "manifest for #{pages_url} names no index artifact"
        end

        new(
          version: 1,
          pages_url: pages_url,
          index: index,
          count: manifest["count"],
          shards: manifest["shards"],
          generated: manifest["generated"],
          sha256: sha,
          bytes: manifest["bytes"],
          captured_at: captured_at,
        )
      end

      # Fetch the site's manifest and return the lock for it. +fetcher+ is the
      # injection point for tests and alternate transports; it must answer
      # (pages_url, **timeouts) with the parsed manifest.
      def self.capture(pages_url, fetcher: nil, open_timeout: 15, read_timeout: 30)
        fetch = fetcher || method(:fetch_manifest)
        from_manifest(
          pages_url,
          fetch.call(pages_url, open_timeout: open_timeout, read_timeout: read_timeout),
        )
      end

      def self.fetch_manifest(pages_url, open_timeout: 15, read_timeout: 30)
        base = pages_url.to_s
        base = "#{base}/" unless base.end_with?("/")
        uri = URI.join(base, "index/manifest.json")
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                  open_timeout:, read_timeout:) do |http|
          http.get(uri.request_uri)
        end
        raise Error, "cannot fetch #{uri}: HTTP #{res.code}" unless res.code == "200"

        Yeptris::JSON.load(res.body)
      rescue Yeptris::JSON::ParseError => e
        raise Error, "malformed manifest at #{uri}: #{e.message}"
      end

      # The published whole-index zip this lock addresses.
      def zip_url
        "#{pages_url.to_s.chomp('/')}/#{index}.zip"
      end

      # Raise unless +data+ is byte-for-byte the artifact this lock pins.
      # Returns true so it reads as an assertion in build scripts.
      def verify(data)
        actual = Digest::SHA256.hexdigest(data)
        if actual != sha256
          raise Error,
                "dataset hash mismatch for #{zip_url}: expected #{sha256}, got #{actual}"
        end
        if bytes && data.bytesize != bytes
          raise Error,
                "dataset size mismatch for #{zip_url}: expected #{bytes} bytes, " \
                "got #{data.bytesize}"
        end

        true
      end
    end
  end
end
