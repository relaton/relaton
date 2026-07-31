module Relaton
  module Ieee
    class Bibliography
      GH_URL = "https://raw.githubusercontent.com/relaton/relaton-data-ieee/refs/heads/v2/".freeze

      class << self
        #
        # Search IEEE bibliography item by reference.
        #
        # @param code [String]
        #
        # @return [Relaton::Ieee::ItemData, nil]
        #
        def search(code) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          index = Relaton::Index.find_or_create :ieee, url: "#{GH_URL}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml",
                                                       pubid_class: ::Pubid::Ieee::Identifier
          # Pass the parsed pubid (not the raw String) so index-v2 narrows
          # candidates by number via binary search before the block runs; the
          # block keeps the broad substring match the string index gave, and an
          # unparseable/partial ref falls back to the full-scan String search.
          # Rows are Pubid::Ieee::Identifier objects (not Comparable), so pick by
          # the string form.
          pubid = parse_pubid code
          needle = pubid.to_s
          row = index.search(pubid) { |r| r[:id].to_s.include?(needle) }.min_by { |r| r[:id].to_s }
          return unless row

          resp = Faraday.get "#{GH_URL}#{row[:file]}"
          return unless resp.status == 200

          Item.from_yaml(resp.body).tap { |item| item.fetched = Date.today.to_s }
        rescue Faraday::ConnectionFailed
          raise Relaton::RequestError, "Could not access #{GH_URL}"
        end

        #
        # Get IEEE bibliography item by reference.
        #
        # @param code [String] the IEEE standard Code to look up (e..g "528-2019")
        # @param year [String] the year the standard was published (optional)
        # @param opts [Hash] options
        #
        # @return [Relaton::Ieee::ItemData, nil]
        #
        def get(code, _year = nil, _opts = {}) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          Util.info "Fetching from Relaton repository ...", key: code
          item = search(code)
          if item
            Util.info "Found: `#{item.docidentifier.first.content}`", key: code
            item
          else
            Util.info "Not found.", key: code
            nil
          end
        end

        private

        # Parse a reference into a Pubid::Ieee::Identifier for index narrowing, or
        # return the raw String when pubid can't parse it (e.g. a partial ref) so
        # the search falls back to the substring scan.
        #
        # @param code [String]
        # @return [::Pubid::Ieee::Identifier, String]
        def parse_pubid(code)
          ::Pubid::Ieee::Identifier.parse code
        rescue StandardError
          code
        end
      end
    end
  end
end
