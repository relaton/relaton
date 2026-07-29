require "net/http"

module Relaton
  module Adobe
    # Retrieval front-end for the Adobe flavor. Looks a reference up in the
    # `relaton-data-adobe` index, fetches the matching YAML record, and
    # deserializes it into a Relaton::Adobe::Item. Mirrors the sibling
    # Relaton::Iala::Bibliography shape.
    module Bibliography
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-adobe/main/".freeze

      class << self
        # Search for an Adobe publication by its identifier.
        #
        # @param text [String] the Adobe reference to look up (e.g.
        #   "Adobe Technical Note #5014", "ATN5014", "Adobe Glyph List")
        # @param _year [String, nil] optional edition/year filter (unused)
        # @param _opts [Hash] options (unused)
        # @return [Relaton::Adobe::Item, nil]
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

          item = Relaton::Adobe::Item.from_yaml resp.body
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
            :adobe,
            url: "#{ENDPOINT}#{INDEXFILE}.zip",
            file: "#{INDEXFILE}.yaml",
          )
        end
      end
    end
  end
end
