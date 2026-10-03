module Relaton
  module Index
    #
    # Configuration class for Relaton::Index
    #
    class Config
      attr_reader :storage, :storage_dir, :filename, :build_sidecar_in_child

      #
      # Set default values
      #
      def initialize
        @storage = FileStorage
        @storage_dir = Dir.home
        @filename = "index.yaml"
        @build_sidecar_in_child = true
      end

      # Build the sidecar in a forked child when available, so the one-time
      # full materialization's memory dies with the child (relaton#242).
      # Set to false to force an in-process build.
      def build_sidecar_in_child=(flag)
        @build_sidecar_in_child = flag
      end

      #
      # Set storage
      #
      # @param [#ctime, #read, #write] storage storage object
      #
      # @return [void]
      #
      def storage=(storage)
        @storage = storage
      end

      #
      # Set storage directory
      #
      # @param [String] dir storage directory
      #
      # @return [void]
      #
      def storage_dir=(dir)
        @storage_dir = dir
      end

      #
      # Set filename
      #
      # @param [String] filename filename
      #
      # @return [void]
      #
      def filename=(filename)
        @filename = filename
      end
    end
  end
end
