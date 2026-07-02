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
      #
      # @return [Relaton::Index::Type] typed index
      #
      def type(type, **args)
        if @pool[type.upcase.to_sym]&.actual?(**args)
          @pool[type.upcase.to_sym]
        else
          @pool[type.upcase.to_sym] = Type.new(type, args[:url], args[:file], args[:id_keys], args[:pubid_class])
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
