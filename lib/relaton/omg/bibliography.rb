# frozen_string_literal: true

module Relaton
  module Omg
    # OMG bibliography module
    module Bibliography
      extend self

      # @param ref [String, Pubid::Omg::Identifier] the OMG standard reference
      # @return [Relaton::Omg::Item]
      def search(ref)
        Scraper.scrape_page ref
      end

      # @param ref [String, Pubid::Omg::Identifier] the OMG standard reference
      # @param year [String] the year the standard was published (optional)
      # @param opts [Hash] options
      # @return [Relaton::Omg::Item]
      def get(ref, _year = nil, _opts = {})
        Util.info "Fetching from www.omg.org ...", key: ref.to_s
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
