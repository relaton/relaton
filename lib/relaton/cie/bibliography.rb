# frozen_string_literal:true

module Relaton
  module Cie
  # IETF bibliography module
    module Bibliography
      class << self
        # @param ref [String, Pubid::Cie::Identifier] the CIE reference (e.g.
        #   "CIE 001-1980"), or its parse from Relaton::Db (relaton#205)
        # @return [Relaton::Cie::ItemData]
        def search(ref)
          Scrapper.scrape_page ref
        end

        # @param ref [String, Pubid::Cie::Identifier] the CIE reference (e.g.
        #   "CIE 001-1980"), or its parse from Relaton::Db (relaton#205)
        # @param year [String] not used
        # @param opts [Hash] not used
        # @return [Relaton::Cie::ItemData] Relaton of reference
        def get(ref, _year = nil, _opts = {})
          Util.info "Fetching from Relaton repository ...", key: ref.to_s
          result = search ref
          if result
            Util.info "Found: `#{result.docidentifier.first.content}`", key: ref.to_s
          else
            Util.info "Not found.", key: ref.to_s
          end
          result
        end
      end
    end
  end
end
