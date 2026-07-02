module Relaton
  module Xsf
    module Bibliography
      extend self

      def search(ref)
        HitCollection.new(ref).search
      end

      def get(code, _year = nil, _opts = {})
        Util.info "Fetching from Relaton repository ...", key: code
        result = search(code)
        if result.empty?
          Util.info "Not found.", key: code
          return
        end

        bib = result.first.item
        Util.info "Found: `#{bib.docidentifier.first.content}`", key: code
        bib
      end
    end
  end
end
