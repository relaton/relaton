module Relaton
  module Index
    #
    # Configuration class for Relaton::Index
    #
    class Config
      attr_reader :storage, :storage_dir, :filename

      #
      # Set default values
      #
      def initialize
        @storage = FileStorage
        @storage_dir = Dir.home
        @filename = "index.yaml"
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
