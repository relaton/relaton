# frozen_string_literal: true

module Relaton
  module Un
    # Class methods for search UN standards.
    class Bibliography
      class << self
        # @param text [String]
        # @return [Relaton::Un::HitCollection]
        def search(text)
          HitCollection.search text
        rescue Faraday::ConnectionFailed, Faraday::TimeoutError,
               Faraday::SSLError => e
          raise Relaton::RequestError,
                "Could not access #{HitCollection::API_BASE}: #{e.message}"
        end

        # @param ref [String, Pubid::Un::Identifier] document reference
        # @param year [String, NilClass]
        # @param opts [Hash] options
        # @return [Relaton::Bib::ItemData]
        def get(ref, _year = nil, _opts = {})
          key = ref.to_s
          Util.info "Fetching from documents.un.org ...", key: key
          item = isobib_search_filter(document_symbol(ref))&.item
          unless item
            Util.info "Not found.", key: key
            return
          end

          Util.info "Found: `#{item.docidentifier[0].content}`", key: key
          item
        end

        private

        # The UN document symbol to search for. A parsed pubid renders it
        # (`TRADE/CEFACT/2004/32`); a String may start with a `UN ` token.
        #
        # @param ref [String, Pubid::Un::Identifier]
        # @return [String]
        def document_symbol(ref)
          return ref.to_s unless ref.is_a?(String)

          ref[/^(?:UN\s)?(.*)/, 1]
        end

        # Search for hits.
        #
        # @param code [String] reference without correction
        # @return [Relaton::Un::Hit, nil]
        def isobib_search_filter(code)
          result = search(code)
          result.select { |i| i.hit["symbols"]&.compact&.include?(code) }.first
        end
      end
    end
  end
end
