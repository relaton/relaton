require "net/http"

module Relaton
  module Iala
    module Bibliography
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-iala/main/".freeze

      class << self
        # Search for an IALA publication by its identifier.
        #
        # @param text [String] the IALA reference to look up (e.g. "IALA S1070")
        # @param _year [String, nil] optional edition/year filter
        # @param _opts [Hash] options (unused)
        # @return [Relaton::Iala::Item, nil]
        def search(text, _year = nil, _opts = {})
          Util.info "Fetching from Relaton repository ...", key: text
          row = index.search(text).max_by { |r| r[:id].to_s }
          unless row
            Util.info "Not found.", key: text
            return
          end

          uri = URI("#{ENDPOINT}#{row[:file]}")
          resp = Net::HTTP.get_response uri
          unless resp.code == "200"
            raise Relaton::RequestError, "Could not access #{uri}: HTTP #{resp.code}"
          end

          item = Relaton::Iala::Item.from_yaml resp.body
          Util.info "Found: `#{item.docidentifier.first&.content}`", key: text
          item.tap { |i| i.fetched = Date.today.to_s }
        rescue SocketError, Errno::EINVAL, Errno::ECONNRESET, EOFError,
               Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
               Net::ProtocolError, Net::ReadTimeout, OpenSSL::SSL::SSLError,
               Errno::ETIMEDOUT => e
          raise Relaton::RequestError, "Could not access #{uri}: #{e.message}"
        end

        def get(ref, year = nil, opts = {})
          search(ref, year, opts)
        end

        private

        def index
          Relaton::Index.find_or_create(
            :iala,
            url: "#{ENDPOINT}#{INDEXFILE}.zip",
            file: "#{INDEXFILE}.yaml",
          )
        end
      end
    end
  end
end
