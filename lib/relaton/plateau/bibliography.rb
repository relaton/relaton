module Relaton
  module Plateau
    module Bibliography
      extend self

      def search(code)
        HitCollection.new(code).find
      end

      def get(code, _year = nil, _opts = {})
        Util.info "Fetching ...", key: code
        result = search(code).fetch_doc
        if result
          Util.info "Found `#{result.docidentifier.first.content}`", key: code
          result
        else
          Util.warn "Not found.", key: code
        end
      rescue StandardError => e
        raise Error, e.message
      end
    end
  end
end
