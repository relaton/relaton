require "mechanize"
require_relative "id_parser"

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
        ref_id = parse_ref reference
        return unless ref_id

        rows = index.search { |r| ref_id == id_hash(r[:id]) }
        return if rows.empty?

        row = rows.max_by { |r| r[:id].year.to_i }
        url = "#{GH_ENDPOINT}#{row[:file]}"
        resp = Mechanize.new.get url
        return unless resp.code == "200"

        item = Item.from_yaml resp.body
        item.fetched = Date.today.to_s
        item
      end

      # Parse a user reference with the flexible bespoke `Id` grammar, which
      # accepts the loose consumer forms (`CCTF Meeting 14 (1999)`,
      # `CCDS …`, `… (2009, EN)`, `SI Brochure Part 1`, …) that the stricter
      # `Pubid::Bipm` grammar rejects. A malformed reference is a graceful miss
      # (nil), not a raised `Relaton::RequestError`.
      #
      # @param reference [String]
      # @return [Relaton::Bipm::Id, nil]
      def parse_ref(reference)
        Id.new.parse reference
      rescue Relaton::RequestError
        nil
      end

      # Project an index row's `Pubid::Bipm` identifier back to the bespoke
      # `{group,type,number,year,…}` hash so the flexible `Id#==` can match it
      # against a parsed user reference. The index stores pubid objects
      # (`_type: pubid:bipm:*`); consumer matching stays on `Id`'s fuzzy
      # equality (number/year/lang collapsing) rather than pubid's stricter
      # stem match, preserving the loose query forms above.
      #
      # @param pubid [Pubid::Bipm::Identifier]
      # @return [Hash]
      def id_hash(pubid) # rubocop:disable Metrics/MethodLength
        case pubid
        when ::Pubid::Bipm::Identifiers::CommitteeDocument
          { group: pubid.group, type: pubid.type_code, number: pubid.number,
            year: pubid.year&.to_s, lang: pubid.language }
        when ::Pubid::Bipm::Identifiers::Meeting
          { group: pubid.group, type: "Meeting", number: pubid.number,
            year: pubid.year&.to_s }
        when ::Pubid::Bipm::Identifiers::MetrologiaArticle
          num = [pubid.volume, pubid.issue, pubid.article].compact.join(" ")
          { group: "Metrologia", number: (num unless num.empty?) }
        when ::Pubid::Bipm::Identifiers::SiBrochure
          { group: "SI", type: "Brochure" }
        else {}
        end.compact
      end

      def index
        Relaton::Index.find_or_create(
          :bipm, url: "#{GH_ENDPOINT}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml",
          pubid_class: ::Pubid::Bipm::Identifier
        )
      end

      # def match_item(ids, ref_id)
      #   ids.find { |id| Id.new(id) == ref_id }
      # end

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
