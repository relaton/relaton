module Relaton
  module Index
    #
    # Pool of indexes
    #
    class Pool
      def initialize
        @pool = {}
      end

      #
      # Return index by type, create if not exists
      #
      # @param [String] type <description>
      # @param [String, nil] url external URL to index, used to fetch index for searching files
      # @param [String, nil] file output file name
      # @param [Array<Symbol>, nil] id_keys keys to check if index is correct
      # @param [String, nil] pages_url base URL of the Pages site that serves
      #   the machine index (manifest + shards), see Relaton::Index::ShardSource
      #
      # @return [Relaton::Index::Type] typed index
      #
      def type(type, **args)
        if @pool[type.upcase.to_sym]&.actual?(**args)
          @pool[type.upcase.to_sym]
        else
          @pool[type.upcase.to_sym] = Type.new(
            type, args[:url], args[:file], args[:id_keys], args[:pubid_class],
            pages_url: args[:pages_url]
          )
        end
      end

      #
      # Remove index by type from pool
      #
      # @param [String] type index type
      #
      # @return [void]
      #
      def remove(type)
        @pool.delete type.upcase.to_sym
      end
    end
  end
end
