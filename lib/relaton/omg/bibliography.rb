# frozen_string_literal: true

module Relaton
  module Omg
    # OMG bibliography module
    module Bibliography
      extend self

      # @param text [String] the OMG standard reference
      # @return [Relaton::Omg::Item]
      def search(text)
        Scraper.scrape_page text
      end

      # @param code [String] the OMG standard reference
      # @param year [String] the year the standard was published (optional)
      # @param opts [Hash] options
      # @return [Relaton::Omg::Item]
      def get(code, _year = nil, _opts = {})
        Util.info "Fetching from www.omg.org ...", key: code
        result = search code
        if result
          Util.info "Found: `#{result.docidentifier.first.content}`", key: code
        else
          Util.info "Not found.", key: code
        end
        result
      end
    end
  end
end
