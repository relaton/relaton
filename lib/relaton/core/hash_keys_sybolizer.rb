module Relaton
  module Core
    module HashKeysSymbolizer
      def symbolize_hash_keys(obj)
        case obj
        when Array
          obj.map { |e| symbolize_hash_keys(e) }
        when Hash
          obj.each_with_object({}) do |(k, v), h|
            key = k.is_a?(String) ? k.to_sym : k
            h[key] = symbolize_hash_keys(v)
          end
        else
          obj
        end
      end
    end
  end
end
