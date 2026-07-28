require "net/http"

module Relaton
  module Gost
    # Retrieval front-end for the GOST flavor. Looks a citation up in the
    # `relaton-data-gost` index and fetches the matching record over HTTP.
    #
    # Plain-string (pubid-free) matching: GOST's `Docidentifier` is a plain
    # `Bib::Docidentifier` today, and `Pubid::Gost` (metanorma/pubid#108) is
    # not yet in the bundle, so `index.search` keys on the bare citation
    # string rather than a parsed identifier. Swap to a `pubid_class` index +
    # `Pubid::Gost` matching (mirroring `Relaton::Oiml::Bibliography`) once #108
    # ships, without changing this public interface.
    module Bibliography
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-gost/main/".freeze

      class << self
        # Search for a GOST publication by its identifier.
        #
        # @param text [String] the GOST reference to look up (e.g.
        #   "GOST R 34.12-2015", "GOST 14946-82", or the Cyrillic "ГОСТ …")
        # @param _year [String, nil] optional edition/year filter (unused today;
        #   the year is carried in the citation string)
        # @param _opts [Hash] options (unused)
        # @return [Relaton::Gost::Item, nil]
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

          item = Relaton::Gost::Item.from_yaml resp.body
          Util.info "Found: `#{item.docidentifier.first&.content}`", key: text
          item.tap { |i| i.fetched = Date.today.to_s }
        rescue SocketError, Errno::EINVAL, Errno::ECONNRESET, EOFError,
               Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
               Net::ProtocolError, Net::ReadTimeout, OpenSSL::SSL::SSLError,
               Errno::ETIMEDOUT => e
          raise Relaton::RequestError, "Could not access #{uri}: #{e.message}"
        end

        # @see #search
        def get(ref, year = nil, opts = {})
          search(ref, year, opts)
        end

        private

        def index
          Relaton::Index.find_or_create(
            :gost,
            url: "#{ENDPOINT}#{INDEXFILE}.zip",
            file: "#{INDEXFILE}.yaml",
          )
        end
      end
    end
  end
end
