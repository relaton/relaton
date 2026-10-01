require "mechanize"

module Relaton
  module Cie
    module Scrapper
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-cie/refs/heads/v2/".freeze

      class << self
        # @param ref [String, Pubid::Cie::Identifier] the reference, or the
        #   parse that Relaton::Db routed with (relaton#205)
        # @return [Relaton::Cie::ItemData]
        def scrape_page(ref)
          # An unrecognized reference raises; like ISO and 3GPP we let it
          # propagate -- relaton-cli rescues Pubid::Errors::Error and renders
          # "... is not a recognized standards identifier". Partial refs
          # (`CIE 001`, `CIE 15`) parse, so nothing valid is lost.
          pubid = to_pubid ref
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

          parse_page "#{ENDPOINT}#{row[:file]}", ref.to_s
        end

        private

        # @param ref [String, Pubid::Cie::Identifier]
        # @return [Pubid::Cie::Identifier] parses only a String
        def to_pubid(ref)
          ref.is_a?(String) ? ::Pubid::Cie.parse(ref) : ref
        end

        # @param url [String]
        # @param ref [String]
        # @retrurn [Relato::Cie::ItemData]
        def parse_page(url, ref)
          resp = Mechanize.new.get url
          Item.from_yaml(resp.body).tap { |item| item.fetched = Date.today.to_s }
        rescue Mechanize::ResponseCodeError => e
          return if e.response_code == "404"

          raise Relaton::RequestError, "No document found for #{ref} reference. #{e.message}"
        rescue Mechanize::RedirectLimitReachedError, Timeout::Error,
            Mechanize::UnauthorizedError, Mechanize::UnsupportedSchemeError,
            Mechanize::ResponseReadError, Mechanize::ChunkedTerminationError => e
          raise Relaton::RequestError, "No document found for #{ref} reference. #{e.message}"
        end
      end
    end
  end
end
