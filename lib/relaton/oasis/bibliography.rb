# frozen_string_literal: true

require "net/http"

module Relaton
  module Oasis
    module Bibliography
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-oasis/refs/heads/v2/"

      class << self
        def search(text, _year = nil, _opts = {}) # rubocop:disable Metrics/MethodLength
          Util.info "Fetching from Relaton repository ...", key: text
          /^(?:OASIS\s)?(?<code>.+)/ =~ text
          row = find_index_entry(code)
          unless row
            Util.info "Not found.", key: text
            return
          end

          uri = URI("#{ENDPOINT}#{row[:file]}")
          parse_item(fetch_yaml(uri), text)
        rescue SocketError, Errno::EINVAL, Errno::ECONNRESET, EOFError,
               Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
               Net::ProtocolError, Net::ReadTimeout,
               OpenSSL::SSL::SSLError, Errno::ETIMEDOUT => e
          raise Relaton::RequestError,
                "Could not access #{uri}: #{e.message}"
        end

        def get(ref, year = nil, opts = {})
          search(ref, year, opts)
        end

        private

        def find_index_entry(code)
          index = Relaton::Index.find_or_create(
            :oasis, url: "#{ENDPOINT}#{INDEXFILE}.zip"
          )
          index.search(code).min_by { |r| r[:id] }
        end

        def fetch_yaml(uri)
          resp = Net::HTTP.get_response uri
          unless resp.code == "200"
            raise Relaton::RequestError,
                  "Could not access #{uri}: HTTP #{resp.code}"
          end
          resp.body
        end

        def parse_item(yaml, text)
          item = Item.from_yaml yaml
          Util.info "Found: `#{item.docidentifier.first.content}`", key: text
          item.tap { |i| i.fetched = Date.today.to_s }
        end
      end
    end
  end
end
