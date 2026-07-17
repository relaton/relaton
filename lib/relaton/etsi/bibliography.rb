# frozen_string_literal: true

module Relaton
  module Etsi
    # Methods for search IANA standards.
    module Bibliography
      SOURCE = "https://raw.githubusercontent.com/relaton/relaton-data-etsi/refs/heads/v2/"

      # @param text [String]
      # @return [Relaton::Etsi::ItemData, nil]
      def search(text) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        index = Relaton::Index.find_or_create :etsi, url: "#{SOURCE}index-v2.zip", file: INDEX_FILE,
                                                     pubid_class: ::Pubid::Etsi::Identifiers::Base
        # Rows carry Pubid::Etsi identifier objects (no `<=>`), so compare their
        # rendered strings to pick the lowest-id match (was a plain string in v1).
        row = index.search(text).min_by { |r| r[:id].to_s }
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

      # @param ref [String] the ETSI standard Code to look up
      # @param year [String, nil] year
      # @param opts [Hash] options
      # @return [Relaton::Etsi::ItemData, nil]
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

      extend Bibliography
    end
  end
end
