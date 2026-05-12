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
        ref_id = Id.new.parse reference
        rows = index.search { |r| ref_id == r[:id] }
        return unless rows.any?

        row = rows.sort_by { |r| r[:id][:year] }.last
        url = "#{GH_ENDPOINT}#{row[:file]}"
        resp = Mechanize.new.get url
        return unless resp.code == "200"

        item = Item.from_yaml resp.body
        item.fetched = Date.today.to_s
        item
      end

      def index
        Relaton::Index.find_or_create(
          :bipm, url: "#{GH_ENDPOINT}index-v1.zip", file: INDEXFILE, id_keys: %i[group type number year corr part append]
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
