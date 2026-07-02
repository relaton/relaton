module Relaton
  module Core
    module ArrayWrapper
      #
      # Wrap into Array if not Array
      #
      # @param [Object] content
      #
      # @return [Array<Object>]
      #
      def array(content)
        case content
        when Array then content
        when nil then []
        else [content]
        end
      end
    end
  end
end
