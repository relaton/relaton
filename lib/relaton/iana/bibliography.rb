# frozen_string_literal: true

module Relaton
  module Iana
    # Methods for search IANA standards.
    module Bibliography
      SOURCE = "https://raw.githubusercontent.com/relaton/relaton-data-iana/refs/heads/v2/"

      # @param text [String]
      # @return [Relaton::Iana::ItemData, nil]
      def search(text) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
        index = Relaton::Index.find_or_create :iana, url: "#{SOURCE}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml"
        id = text.sub(/^IANA\s/, "")
        row = index.search(id).min_by { |i| i[:id] }
        return unless row

        url = "#{SOURCE}#{row[:file]}"
        resp = Net::HTTP.get_response URI(url)
        return unless resp.code == "200"

        Item.from_yaml(resp.body).tap { |item| item.fetched = Date.today.to_s }
      rescue SocketError, Timeout::Error, Errno::EINVAL, Errno::ECONNRESET,
             EOFError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
             Net::ProtocolError, Errno::ETIMEDOUT => e
        raise Relaton::RequestError, e.message
      end

      # @param ref [String] the W3C standard Code to look up
      # @param year [String, NilClass] not used
      # @param opts [Hash] options
      # @return [Relaton::Iana::ItemData, nil]
      def get(ref, _year = nil, _opts = {})
        Util.info "Fetching from Relaton repository ...", key: ref
        result = search(ref)
        unless result
          Util.info "Not found.", key: ref
          return
        end

        Util.info "Found: `#{result.docidentifier[0].content}`", key: ref
        result
      end

      extend self
    end
  end
end
