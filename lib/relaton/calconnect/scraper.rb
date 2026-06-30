require "mechanize"
require "stringio"
require "zip"
require_relative "model/item"
require_relative "model/bibdata"

module Relaton
  module Calconnect
    class Scraper
      include Core::HashKeysSymbolizer
      include Core::ArrayWrapper

      RELEASE_ASSET_URL = "https://github.com/%<owner>s/%<repo>s/releases/download/" \
                          "%<tag>s/%<asset_stem>s.zip".freeze

      # @param errors [Hash] error tracking hash
      def initialize(errors = {})
        @errors = errors
      end

      #
      # Parse an aggregate-index document entry: download the per-document
      # GitHub release zip, extract the RXL, and parse it into a bibitem.
      #
      # @param hit [Hash] document entry from /cc/index.json
      #
      # @return [Relaton::Calconnect::ItemData] bibliographic item
      #
      def parse_page(hit)
        zip_data = download_release_zip hit
        rxl = extract_rxl zip_data, rxl_filename(hit)
        xml = normalize_rxl rxl
        Item.from_xml xml
      end

      private

      def release_zip_url(hit)
        source = hit["source"] || {}
        format(
          RELEASE_ASSET_URL,
          owner: source["owner"],
          repo: source["repo"],
          tag: source["tag"],
          asset_stem: asset_stem(hit),
        )
      end

      def rxl_filename(hit)
        "#{asset_stem(hit)}.rxl"
      end

      # The release asset uses the tag with the slash replaced by a hyphen,
      # which encodes both the document id and the release qualifier
      # (e.g. `ed1`, `ed1-wd`).
      def asset_stem(hit)
        (hit["source"] && hit["source"]["tag"] || "").tr("/", "-")
      end

      def download_release_zip(hit)
        url = release_zip_url(hit)
        agent.get(url).body
      rescue Mechanize::ResponseCodeError => e
        raise "Failed to download release zip #{url}: HTTP #{e.response_code}"
      end

      def agent
        @agent ||= Mechanize.new
      end

      def extract_rxl(zip_data, filename)
        Zip::File.open_buffer(StringIO.new(zip_data)) do |zip|
          entry = zip.find_entry(filename)
          raise "RXL file #{filename} not found in release zip" unless entry

          return entry.get_input_stream.read
        end
      end

      def normalize_rxl(xml)
        xml.gsub(%r{(</?)technical-committee(>)}, '\1committee\2')
          .gsub(%r{type="(?:csd|CC)"(?=>)}i, '\0 primary="true"')
          .gsub(%r{type="Technical committee"}, 'type="technical-committee"')
      end
    end
  end
end
