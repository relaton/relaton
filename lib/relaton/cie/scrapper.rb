require "mechanize"

module Relaton
  module Cie
    module Scrapper
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-cie/refs/heads/v2/".freeze

      class << self
        # @param code [String]
        # @return [Relaton::Cie::ItemData]
        def scrape_page(code)
          # An unrecognized reference raises; like ISO and 3GPP we let it
          # propagate -- relaton-cli rescues Parslet::ParseFailed and renders
          # "... is not a recognized standards identifier". Partial refs
          # (`CIE 001`, `CIE 15`) parse, so nothing valid is lost.
          pubid = ::Pubid::Cie.parse code
          index = Index.find_or_create :cie, url: "#{ENDPOINT}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml",
                                              pubid_class: ::Pubid::Cie::Identifier
          # Pass the parsed pubid (not the raw String) so index-v2 narrows
          # candidates by number via binary search before the block runs; the
          # block keeps the broad substring match the string index gave.
          # Rows are Pubid::Cie::Identifier objects (not Comparable), so pick by
          # the string form.
          needle = pubid.to_s
          row = index.search(pubid) { |r| r[:id].to_s.include?(needle) }
                     .min_by { |r| r[:id].to_s }
          return unless row

          parse_page "#{ENDPOINT}#{row[:file]}", code
        end

        private

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
