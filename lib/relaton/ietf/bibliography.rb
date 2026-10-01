# frozen_string_literal:true

require_relative "scraper"

module Relaton
  module Ietf
  # IETF bibliography module
    module Bibliography
      class << self
        # @param ref [String, Pubid::Ietf::Identifier] the IETF reference
        #   (e.g. "RFC 8341"), or its parse from Relaton::Db (relaton#205)
        # @return [RelatonIetf::IetfBibliographicItem]
        def search(ref)
          Scraper.scrape_page ref
        end

        # @param ref [String, Pubid::Ietf::Identifier] the IETF reference
        #   (e.g. "RFC 8341"), or its parse from Relaton::Db (relaton#205)
        # @param year [String] the year the standard was published (optional)
        # @param opts [Hash] options; restricted to :all_parts if all-parts
        #   reference is required
        # @return [RelatonIetf::IetfBibliographicItem] Relaton of reference
        def get(ref, _year = nil, _opts = {})
          Util.info "Fetching from Relaton repository ...", key: ref.to_s
          result = search ref
          if result
            docid = result.docidentifier.detect(&:primary) || result.docidentifier.first
            Util.info "Found: `#{docid.content}`", key: ref.to_s
          else
            Util.info "Not found.", key: ref.to_s
          end
          result
        end
      end
    end
  end
end
