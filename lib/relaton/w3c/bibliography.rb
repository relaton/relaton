# frozen_string_literal: true

require "net/http"
require "relaton/bib/hash_parser_v1"
require_relative "pubid"

module Relaton
  module W3c
    # Class methods for search W3C standards.
    class Bibliography
      SOURCE = "https://raw.githubusercontent.com/relaton/relaton-data-w3c/v2/"

      class << self
        # @param text [String]
        # @return [Relaton::W3c::ItemData]
        def search(text) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
          pubid = PubId.parse text.sub(/^W3C\s/, "")
          index = Relaton::Index.find_or_create(
            :W3C, url: "#{SOURCE}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml", id_keys: PubId::PARTS,
          )
          row = index.search { |r| pubid == r[:id] }.sort_by { |r| (r[:id][:date] || r[:id][:year]).to_i }.last
          return unless row

          url = "#{SOURCE}#{row[:file]}"
          resp = Net::HTTP.get_response(URI.parse(url))
          return unless resp.code == "200"

          Item.from_yaml(resp.body).tap { |i| i.fetched = Date.today.to_s }
        rescue SocketError, Timeout::Error, Errno::EINVAL, Errno::ECONNRESET,
               EOFError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
               Net::ProtocolError, Errno::ETIMEDOUT => e
          raise Relaton::RequestError, "Could not access #{url}: #{e.message}"
        end

        # @param ref [String] the W3C standard Code to look up
        # @param year [String, NilClass] not used
        # @param opts [Hash] options
        # @return [Relaton::W3c::ItemData]
        def get(ref, _year = nil, _opts = {})
          Util.info "Fetching from Relaton repository ...", key: ref
          result = search(ref)
          unless result
            Util.info "Not found.", key: ref
            return
          end

          found = result.docidentifier.first.content
          Util.info "Found: `#{found}`", key: ref
          result
        end
      end
    end
  end
end
