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
        # @param year [String, nil] the year, when the reference has none
        #
        # @return [Relaton::Ieee::ItemData, nil]
        #
        def search(ref, year = nil)
          row = find_row parse_pubid(ref), year
          return unless row

          resp = Faraday.get "#{GH_URL}#{row[:file]}"
          return unless resp.status == 200

          Item.from_yaml(resp.body).tap { |item| item.fetched = Date.today.to_s }
        rescue Faraday::ConnectionFailed
          raise Relaton::RequestError, "Could not access #{GH_URL}"
        end

        #
        # Get IEEE bibliography item by reference. An undated reference
        # answers with the latest edition as an undated item that has an
        # `instanceOf` relation to that edition (relaton-ieee#29).
        #
        # @param ref [String, Pubid::Ieee::Identifier] the IEEE standard
        #   reference to look up (e.g. "IEEE 528-2019"), or its parse from
        #   Relaton::Db (relaton#205)
        # @param year [String] the year the standard was published (optional)
        # @param opts [Hash] options
        # @option opts [Boolean] :keep_year keep the edition's date on an
        #   undated reference
        #
        # @return [Relaton::Ieee::ItemData, nil]
        #
        def get(ref, year = nil, opts = {}) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          Util.info "Fetching from Relaton repository ...", key: ref.to_s
          item = search(ref, year)
          unless item
            Util.info "Not found.", key: ref.to_s
            return
          end

          Util.info "Found: `#{item.docidentifier.first.content}`", key: ref.to_s
          return item if opts[:keep_year] || dated?(parse_pubid(ref), year)

          item.to_most_recent_reference
        end

        private

        # The index row of the reference. A parsed reference matches the rows
        # of its own document by pubid equality, the year aside; an undated
        # one takes the latest edition. When that finds nothing (an
        # unparseable reference, or a form whose year pubid keeps elsewhere)
        # the broad substring match is the fallback.
        #
        # @param pubid [Pubid::Ieee::Identifier, String]
        # @param year [String, nil]
        # @return [Hash, nil] the `{ id:, file: }` row
        def find_row(pubid, year)
          index = Relaton::Index.find_or_create :ieee, pages_url: PAGES_URL,
                                                       pubid_class: ::Pubid::Ieee::Identifier
          row = pubid_row(index, pubid, year) unless pubid.is_a?(String)
          row || substring_row(index, pubid)
        end

        # Not `pubid === row`: IEEE `parts`, `prefix`, `draft` and
        # `draft_status` are not `subset_strict` in pubid, so a nil there is a
        # wildcard and `IEEE 802.3` would match `IEEE Std 802.3.1-2011` and
        # `IEEE Unapproved P802.3/D2.0`.
        def pubid_row(index, pubid, year)
          target = (pubid.year || year)&.to_s
          base = pubid.exclude(:year)
          rows = index.search(pubid) do |r|
            id = r[:id]
            id.is_a?(::Pubid::Ieee::Identifier) && id.exclude(:year) == base &&
              (target.nil? || id.year.to_s == target)
          end
          return rows.min_by { |r| r[:id].to_s } if target

          rows.max_by { |r| [r[:id].year.to_s, r[:id].to_s] }
        end

        # pubid's normalization moves a legacy base year into its own comma
        # segment ("IEEE P802.16/D5, 2004/Cor. 1-2005"); the index rows carry
        # the canonical form without it, so the block also matches with the
        # moved year stripped. Rows are Pubid::Ieee::Identifier objects (not
        # Comparable), so pick by the string form.
        #
        # The project prefix moves too: "IEEE P802.21/D14" parses as a
        # ProjectDraft, but the pre-publication crawl records spell the same
        # document "IEEE Unapproved 802.21/D14, Sept 2008" — the Unapproved
        # draft status occupies the slot the publisher and P would render in,
        # so the row string contains neither (relaton-ieee#25). The draft
        # number "/D14" still has to match, so the bare form cannot reach the
        # published standard or a different draft — the variant exists only
        # for a reference that names its draft.
        def substring_row(index, pubid)
          needle = pubid.to_s
          # The publisher-and-prefix-stripped form; nil when there is no
          # project-prefixed draft number.
          stripped = needle.sub("IEEE P", "") if needle.match?(/\AIEEE P\S*\/D\d/i)
          index.search(pubid) do |r|
            id = r[:id].to_s
            id.include?(needle) ||
              id.include?(needle.gsub(/, (19|20)\d{2}\//, "/")) ||
              (stripped && id.include?(stripped))
          end.min_by { |r| r[:id].to_s }
        end

        # @param pubid [Pubid::Ieee::Identifier, String]
        # @param year [String, nil]
        def dated?(pubid, year)
          return true if year
          return pubid.year if pubid.respond_to?(:year)

          # An unparseable reference was found by substring; leave it dated.
          true
        end

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
