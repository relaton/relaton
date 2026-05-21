# frozen_string_literal: true

require "yaml"
require "zip"
require "relaton/logger"
require "pubid-core"

require_relative "index/version"
require_relative "index/file_storage"
require_relative "index/config"
require_relative "index/util"
require_relative "index/pool"
require_relative "index/type"
require_relative "index/file_io"

module Relaton
  module Index
    class Error < StandardError; end

    class << self
      #
      # Proxy for Pool#type
      #
      def find_or_create(type, **args)
        pool.type(type, **args)
      end

      def close(type)
        pool.remove type
      end

      #
      # Create new index pool object or return existing
      #
      # @return [Relaton::Index::Pool] index pool
      #
      def pool
        @pool ||= Pool.new
      end

      #
      # Create new config object or return existing
      #
      # @return [Relaton::Index::Config] config object
      #
      def config
        @config ||= Config.new
      end

      #
      # Configure Relaton::Index
      #
      # @return [void]
      #
      def configure
        yield config
      end
    end
  end
end
