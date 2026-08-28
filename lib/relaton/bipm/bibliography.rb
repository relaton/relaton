require "mechanize"

module Relaton::Bipm
  class Bibliography
    GH_ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-bipm/refs/heads/v2/".freeze

    class << self
      # @param text [String]
      # @return [RelatonBipm::BipmBibliographicItem]
      def search(text, _year = nil, _opts = {}) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        Util.info "Fetching from Relaton repository ...", key: text
        ref = text.sub(/^BIPM\s/, "")
        item = get_bipm ref
        unless item
          Util.info "Not found.", key: text
          return
        end

        Util.info "Found: `#{item.docidentifier[0].content}`", key: text
        item
      rescue Mechanize::ResponseCodeError => e
        raise Relaton::RequestError, e.message unless e.response_code == "404"
      end

      # @return [Mechanize]
      # def magent # rubocop:disable Metrics/MethodLength
      #   a = Mechanize.new
      #   a.request_headers = {
      #     "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9," \
      #                 "image/avif,image/webp,image/apng," \
      #                 "*/*;q=0.8,application/signed-exchange;v=b3;q=0.9",
      #     "Accept-Encoding" => "gzip, deflate, br",
      #     "Accept-Language" => "en-US,en;q=0.9,ru-RU;q=0.8,ru;q=0.7",
      #     "Cache-Control" => "max-age=0",
      #     "Upgrade-Insecure-Requests" => "1",
      #   }
      #   a.user_agent_alias = Mechanize::AGENT_ALIASES.map(&:first).shuffle.first
      #   # a.user_agent_alias = "Mac Safari"
      #   a
      # end

      #
      # @param reference [String]
      #
      # @return [RelatonBipm::BipmBibliographicItem]
      #
      def get_bipm(reference) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        pubid = parse_ref reference
        return unless pubid

        rows = search_index pubid, reference
        return if rows.empty?

        # Latest edition wins. Metrologia and SI Brochure rows carry no year,
        # so they all score 0; the file path breaks that tie so a repeated
        # lookup returns the same document (the index sort is not stable).
        row = rows.max_by { |r| [r[:id].year.to_i, r[:file]] }
        url = "#{GH_ENDPOINT}#{row[:file]}"
        resp = Mechanize.new.get url
        return unless resp.code == "200"

        item = Item.from_yaml resp.body
        item.fetched = Date.today.to_s
        item
      end

      # Look the reference up in the pubid `index-v2`, narrowing the candidate
      # rows before the match runs. `Relaton::Index::Type#search` binary-searches
      # only when given an identifier — the same call shape ISO, OIML and JCGM
      # use. Both sides are now `Pubid::Bipm` objects, so the bespoke `Id`
      # grammar takes no part in a query.
      #
      # Two escapes sit under the narrowing, each covering a case where the
      # query's bsearch key cannot equal its row's:
      #
      # 1. A bare `SI Brochure` names no edition, so it keys to `""` while its
      #    row keys to `"9e"`. The rescan finds it.
      # 2. `CCTF Recommendation 2009-02` parses as the literal number
      #    `2009-02`, while the row keys on `2`. No row carries that number, so
      #    a rescan cannot help — only re-reading the tail as number-plus-year.
      #
      # @param pubid [Pubid::Bipm::Identifier] the parsed reference
      # @param reference [String, nil] the raw reference, for the retry
      # @return [Array<Hash>] the matching index rows
      def search_index(pubid, reference)
        # Reduce the query once, not once per row. `#exclude` copies the
        # identifier, so rebuilding it per candidate dominated the lookup.
        query_stem = stem pubid, pubid
        rows = index.search(pubid) { |r| pubid_match? r[:id], pubid, query_stem }
        rows = index.search { |r| pubid_match? r[:id], pubid, query_stem } if rows.empty?
        return rows unless rows.empty?

        retry_pubid = year_number_retry reference
        retry_pubid ? search_index(retry_pubid, nil) : rows
      end

      # Re-read a trailing `YYYY-NN` as number `NN` of year `YYYY`
      # (`CCTF Recommendation 2009-02` → `CCTF Recommendation 2 (2009)`). Tried
      # only after a miss, because `NNNN-NN` is also a real BIPM number
      # (`CIPM 2005-06`), so the literal reading has to be preferred.
      #
      # @param reference [String, nil]
      # @return [Pubid::Bipm::Identifier, nil]
      def year_number_retry(reference)
        match = reference&.match(/\A(?<stem>.+)\s(?<year>\d{4})-(?<number>\d+)\z/)
        return unless match

        parse_ref "#{match[:stem]} #{match[:number].sub(/\A0+(?=\d)/, '')} (#{match[:year]})"
      end

      # Compare a row's identifier with the query. Index rows are stored
      # language- and form-neutral — verified across all committee-document and
      # meeting rows — while a reference may name a language (`(2009, E)`) and
      # always names a form (short `CCTF REC 2` vs long `CCTF Recommendation 2`).
      # The year joins them when the query omits it, mirroring what `Id#==` did
      # with `other_hash.delete(:year) unless hash[:year]`.
      #
      # @param row_id [Pubid::Bipm::Identifier]
      # @param query [Pubid::Bipm::Identifier]
      # @param query_stem [Pubid::Bipm::Identifier, nil] the reduced query, when
      #   the caller already built it once for the whole search
      # @return [Boolean]
      def pubid_match?(row_id, query, query_stem = nil)
        # A bare brochure names no edition, so it is a partial reference and
        # cannot equal the `9e v3.01` row. Match any brochure row, which is what
        # the old `{group: "SI", type: "Brochure"}` projection already meant.
        if query.is_a?(::Pubid::Bipm::Identifiers::SiBrochure) && query.edition.nil?
          return row_id.is_a?(::Pubid::Bipm::Identifiers::SiBrochure)
        end

        return false unless row_id.instance_of?(query.class)

        # `Id#==` treated a document numbered "1" and a number-less one as the
        # same document when both carried a year, so `CIPM Resolution 1 (1879)`
        # reached `CIPM RES (1879)`. pubid has no such rule and the six
        # ordinal-less declarations are only addressable this way, so keep it.
        if number_collapses?(row_id, query)
          keys = stem_keys(query) + [:number]
          return row_id.exclude(*keys) == query.exclude(*keys)
        end

        return false unless cheap_reject_passes?(row_id, query)

        stem(row_id, query) == (query_stem || stem(query, query))
      end

      # @param row_id [Pubid::Bipm::Identifier]
      # @param query [Pubid::Bipm::Identifier]
      # @return [Boolean] true when one side is number-less, the other is
      #   numbered "1", and both carry a year
      def number_collapses?(row_id, query)
        return false unless row_id.year && query.year

        numbers = [row_id.number.to_s, query.number.to_s]
        numbers.include?("") && numbers.include?("1")
      end

      # Attributes the stem never removes, so stem equality implies equality on
      # every one of them. Comparing them first cannot change the answer, it
      # only avoids the reduction — and `#exclude` copies the identifier, which
      # is what made an unguarded compare cost roughly 165x a plain attribute
      # read and turned a rescan into seconds.
      CHEAP_KEYS = %i[number group year issue article].freeze

      # @param row_id [Pubid::Bipm::Identifier]
      # @param query [Pubid::Bipm::Identifier]
      # @return [Boolean] false as soon as one cheap attribute differs
      def cheap_reject_passes?(row_id, query)
        CHEAP_KEYS.all? do |key|
          # `:year` is dropped from the stem when the query has none, so it is
          # only significant when the query supplies one.
          next true if key == :year && query.year.nil?
          next true unless query.respond_to?(key) && row_id.respond_to?(key)

          row_id.public_send(key).to_s == query.public_send(key).to_s
        end
      end

      # @param pubid [Pubid::Bipm::Identifier] the identifier to reduce
      # @param query [Pubid::Bipm::Identifier] the query that sets which
      #   attributes are significant
      # @return [Pubid::Bipm::Identifier] a copy; the cached row id is untouched
      def stem(pubid, query)
        pubid.exclude(*stem_keys(query))
      end

      # @param query [Pubid::Bipm::Identifier]
      # @return [Array<Symbol>] the attributes a match must ignore
      def stem_keys(query)
        keys = %i[language form]
        keys << :year if query.year.nil?
        keys
      end

      # Parse a user reference with `Pubid::Bipm`, which since pubid `a96e9f45`
      # accepts the loose consumer forms this flavor once needed `Id` for
      # (`CCDS Recommendation 2 (2009)`, `CIPM 111e Réunion (2022)`,
      # `CCTF Meeting 14 (1999)`, `SI Brochure Part 1`, …) and normalizes them
      # to BIPM's canonical spelling. A malformed reference is a graceful miss
      # (nil), not a raised error.
      #
      # @param reference [String]
      # @return [Pubid::Bipm::Identifier, nil]
      def parse_ref(reference)
        ::Pubid::Bipm.parse reference
      rescue StandardError
        nil
      end

      def index
        Relaton::Index.find_or_create(
          :bipm, url: "#{GH_ENDPOINT}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml",
          pubid_class: ::Pubid::Bipm::Identifier
        )
      end

      # @param ref [String] the BIPM standard Code to look up (e..g "BIPM B-11")
      # @param year [String] not used
      # @param opts [Hash] not used
      # @return [RelatonBipm::BipmBibliographicItem]
      def get(ref, year = nil, opts = {})
        search(ref, year, opts)
      end
    end
  end
end
