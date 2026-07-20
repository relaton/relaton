require "mechanize"

module Relaton
  module Cie
    module Scrapper
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-cie/refs/heads/v2/".freeze

      class << self
        # @param code [String]
        # @return [Relaton::Cie::ItemData]
        def scrape_page(code)
          index = Index.find_or_create :cie, url: "#{ENDPOINT}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml",
                                              pubid_class: ::Pubid::Cie::Identifier
          # Pass the parsed pubid (not the raw String) so index-v2 narrows
          # candidates by number via binary search before the block runs; the
          # block keeps the broad substring match the string index gave, and an
          # unparseable/partial ref falls back to the full-scan String search.
          # Rows are Pubid::Cie::Identifier objects (not Comparable), so pick by
          # the string form.
          pubid = parse_pubid code
          needle = pubid.to_s
          row = index.search(pubid) { |r| r[:id].to_s.include?(needle) }
                     .min_by { |r| r[:id].to_s }
          return unless row

          parse_page "#{ENDPOINT}#{row[:file]}", code
        end

        private

        # Parse a reference into a Pubid::Cie::Identifier for index narrowing, or
        # return the raw String when pubid can't parse it (e.g. a partial ref) so
        # the search falls back to the substring scan.
        def parse_pubid(code)
          ::Pubid::Cie.parse code
        rescue StandardError
          code
        end

        # @param url [String]
        # @param code [String]
        # @retrurn [Relato::Cie::ItemData]
        def parse_page(url, code)
          resp = Mechanize.new.get url
          Item.from_yaml(resp.body).tap { |item| item.fetched = Date.today.to_s }
        rescue Mechanize::ResponseCodeError => e
          return if e.response_code == "404"

          raise Relaton::RequestError, "No document found for #{code} reference. #{e.message}"
        rescue Mechanize::RedirectLimitReachedError, Timeout::Error,
            Mechanize::UnauthorizedError, Mechanize::UnsupportedSchemeError,
            Mechanize::ResponseReadError, Mechanize::ChunkedTerminationError => e
          raise Relaton::RequestError, "No document found for #{code} reference. #{e.message}"
        end
      end
    end
  end
end
