# frozen_string_literal: true

module Relaton
  module Sdo
    # Configuration for the SDO org/logo store: where the index manifest lives,
    # where to cache it, and for how long. Mirrors Relaton::Index::Config; the
    # storage backend is swappable (e.g. an S3-backed object) via `storage=`.
    class Config
      # Default published index of the relaton-data-sdo data repo.
      DEFAULT_URL =
        "https://raw.githubusercontent.com/relaton/relaton-data-sdo/main/index.yaml"

      attr_accessor :url, :storage, :storage_dir, :ttl

      def initialize
        @url = DEFAULT_URL
        @storage = Relaton::Index::FileStorage
        @storage_dir = File.join(Dir.home, ".relaton", "sdo")
        @ttl = 24 * 60 * 60 # seconds
      end
    end

    class << self
      def configuration
        @configuration ||= Config.new
      end

      def configure
        yield configuration if block_given?
        configuration
      end
    end
  end
end
