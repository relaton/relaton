module Relaton
  module Ieee
    class Bibliography
      GH_URL = "https://raw.githubusercontent.com/relaton/relaton-data-ieee/refs/heads/v2/".freeze

      class << self
        #
        # Search IEEE bibliography item by reference.
        #
        # @param ref [String, Pubid::Ieee::Identifier] the reference, or its
        #   parse from Relaton::Db (relaton#205)
        #
        # @return [Relaton::Ieee::ItemData, nil]
        #
        def search(ref) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          index = Relaton::Index.find_or_create :ieee, url: "#{GH_URL}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml",
                                                       pubid_class: ::Pubid::Ieee::Identifier
          # Pass the parsed pubid (not the raw String) so index-v2 narrows
          # candidates by number via binary search before the block runs; the
          # block keeps the broad substring match the string index gave, and an
          # unparseable/partial ref falls back to the full-scan String search.
          # Rows are Pubid::Ieee::Identifier objects (not Comparable), so pick by
          # the string form.
          pubid = parse_pubid ref
          needle = pubid.to_s
          # pubid's normalization moves a legacy base year into its own
          # comma segment ("IEEE P802.16/D5, 2004/Cor. 1-2005"); the
          # index rows carry the canonical form without it, so the
          # block also matches with the moved year stripped
          row = index.search(pubid) do |r|
            id = r[:id].to_s
            id.include?(needle) ||
              id.include?(needle.gsub(/, (19|20)\d{2}\//, "/"))
          end.min_by { |r| r[:id].to_s }
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
        # @param ref [String, Pubid::Ieee::Identifier] the IEEE standard
        #   reference to look up (e.g. "IEEE 528-2019"), or its parse from
        #   Relaton::Db (relaton#205)
        # @param year [String] the year the standard was published (optional)
        # @param opts [Hash] options
        #
        # @return [Relaton::Ieee::ItemData, nil]
        #
        def get(ref, _year = nil, _opts = {}) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          Util.info "Fetching from Relaton repository ...", key: ref.to_s
          item = search(ref)
          if item
            Util.info "Found: `#{item.docidentifier.first.content}`", key: ref.to_s
            item
          else
            Util.info "Not found.", key: ref.to_s
            nil
          end
        end

        private

        # Parse a reference into a Pubid::Ieee::Identifier for index narrowing, or
        # return the raw String when pubid can't parse it (e.g. a partial ref) so
        # the search falls back to the substring scan.
        #
        # @param ref [String, ::Pubid::Ieee::Identifier]
        # @return [::Pubid::Ieee::Identifier, String]
        def parse_pubid(ref)
          # A pubid from Relaton::Db (relaton#205) is used as it is.
          return ref unless ref.is_a?(String)

          ::Pubid::Ieee::Identifier.parse ref
        rescue StandardError
          ref
        end
      end
    end
  end
end
