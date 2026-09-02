require "faraday"
require_relative "hit"

module Relaton
  module Ogc
    class HitCollection < Core::HitCollection
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-ogc/v2/".freeze

      # @return [self]
      def find
        return self if ref.nil? || ref.empty?

        row = best_match ref
        return self unless row

        url = "#{ENDPOINT}#{row[:file]}"
        resp = Faraday.get(url) { |req| req.options.timeout = 10 }
        return self unless resp.status == 200

        item = Item.from_yaml resp.body
        item.fetched = Date.today.to_s
        hit = Hit.new({ code: item.docidentifier[0]&.content, file: row[:file] }, self)
        hit.instance_variable_set(:@item, item)
        @array = [hit]
        self
      end

      # @return [Relaton::Index::Type]
      def index
        @index ||= Relaton::Index.find_or_create(
          :ogc, url: "#{ENDPOINT}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml",
          pubid_class: ::Pubid::Ogc::Identifier
        )
      end

      private

      #
      # Find the index row for a reference, latest revision first.
      #
      # Passing the pubid to `Index::Type#search` is what enables the binary
      # search on `id.root.number` — with the plain string this used to pass,
      # the whole index is scanned however the index was built. `revision` is
      # OGC's only optional component, so the ETSI idiom reduces to ignoring it
      # when the reference omits it: that is how a bare `OGC 12-128` still finds
      # the `r19` row. `year` is never ignorable — the bsearch key is the
      # `<nnn>` field alone, so one bucket holds every year that reused the
      # number (`05-007` and `17-007` share bucket `007`).
      #
      # A reference pubid cannot parse falls back to the previous behaviour, a
      # full scan matching `id.to_s` as a substring.
      #
      # @param text [String]
      # @return [Hash, nil]
      #
      def best_match(text)
        pubid = parse_ref text
        rows = if pubid
                 index.search(pubid) { |r| pubid.matches?(r[:id], ignore: ignored(pubid)) }
               else
                 index.search text
               end
        rows.max_by { |r| [revision_key(r[:id].revision), r[:file]] }
      end

      # The components the reference left out, which the row may carry freely.
      #
      # @param pubid [Pubid::Ogc::Identifier]
      # @return [Array<Symbol>]
      #
      def ignored(pubid)
        pubid.revision.nil? ? %i[revision] : []
      end

      #
      # Order key for an OGC revision suffix.
      #
      # Revisions are `r<n>` with optional letter suffixes (`r3a`, `r12a`) plus
      # the odd `a` and `c1`, so the number must be compared as an integer:
      # `r2` beats `r14` as text but is the older document. The token itself
      # breaks the tie, so `r3a` sorts above `r3` and a repeated lookup returns
      # the same row (the index sort is not stable). An absent revision sorts
      # below every present one.
      #
      # Highest revision is the newest published document in 105 of the 106
      # multi-revision documents in the index, scored against each document's
      # own `date[0].at`; the previous `min_by` on the rendered id matched 1.
      #
      # @param revision [String, nil]
      # @return [Array]
      #
      def revision_key(revision)
        [revision.to_s[/\d+/].to_i, revision.to_s]
      end

      #
      # Parse a user reference into a `Pubid::Ogc::Identifier`, or nil.
      #
      # `Pubid::Ogc` takes the `OGC ` publisher token as optional and
      # lowercases the revision, so `OGC 19-025r1`, `19-025r1`, `11-038R2` and
      # the revision-less `16-079` all parse without normalization here.
      #
      # @param text [String]
      # @return [Pubid::Ogc::Identifier, nil]
      #
      def parse_ref(text)
        ::Pubid::Ogc::Identifier.parse text.to_s.strip
      rescue StandardError => e
        Util.warn "Failed to parse pubid `#{text}`: #{e.message}"
        nil
      end
    end
  end
end
