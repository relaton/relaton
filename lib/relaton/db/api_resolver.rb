require "net/http"
require "uri"
require "openssl"
require "zlib"
require_relative "../version"

module Relaton
  class Db
    #
    # The api.relaton.org tier of a `Db` fetch (relaton#535): local cache,
    # then this, then the flavor's own `get`.
    #
    # It reads `GET <api_host>/v3/documents/<key>` as Relaton YAML, where the
    # key is one percent-encoded path segment. The API is not authoritative
    # while its coverage is verified per flavor, so every answer it cannot
    # give with certainty is nil, and `Db#fetch_doc` then asks the flavor:
    # a 404, any other status, a transport failure, and a body the flavor
    # cannot read. Nothing here raises, and nothing here touches the cache:
    # `Db` stores the answer as it stores a flavor's.
    #
    module ApiResolver
      ACCEPT = "application/yaml".freeze
      # The transport failures that mean "ask the flavor" (the list of
      # `Index::ShardSource::NET_ERRORS`; not required from there, so that
      # `require "relaton/db"` opens no partial `Relaton::Index`).
      NET_ERRORS = [
        SocketError, Timeout::Error, IOError, SystemCallError,
        OpenSSL::SSL::SSLError, Net::HTTPBadResponse,
        Net::HTTPHeaderSyntaxError, Net::ProtocolError, Zlib::Error
      ].freeze

      module_function

      #
      # @param processor [Relaton::Core::Processor] the routed flavor
      # @param key [Pubid::Identifier] the query's cache key; the API is
      #   asked for its rendering
      # @return [Relaton::Bib::ItemData, nil] nil: ask the flavor
      #
      def fetch(processor, key)
        body = get(key.to_s) or return

        read(processor, body, key)
      end

      # @return [String, nil] the body of a 200, else nil
      def get(ref)
        host = Db.configuration.api_host.chomp("/")
        uri = URI("#{host}/v3/documents/#{escape(ref)}")
        rsp = request(uri)
        return rsp.body if rsp.code == "200"

        info "HTTP #{rsp.code}", ref
        nil
      rescue *NET_ERRORS => e
        info "#{e.class}: #{e.message}", ref
        nil
      end

      def request(uri)
        timeout = Db.configuration.api_timeout
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                            open_timeout: timeout,
                                            read_timeout: timeout) do |http|
          http.get(uri.request_uri, "Accept" => ACCEPT,
                                    "User-Agent" => "relaton/#{Relaton::VERSION}")
        end
      end

      # The API's body is data: a body the flavor's YAML model rejects, or
      # one that is not a document (`--- []` reads as an Array), is a miss,
      # whatever the model raises for it.
      def read(processor, body, ref)
        item = processor.from_yaml body
        return item if item.is_a?(Relaton::Bib::ItemData)

        info "answer is not a document (#{item.class})", ref
        nil
      rescue StandardError => e
        info "unreadable answer (#{e.class}: #{e.message})", ref
        nil
      end

      # One path segment: `/` and `:` are escaped, a space is `%20`.
      def escape(ref)
        URI.encode_www_form_component(ref).gsub("+", "%20")
      end

      def info(reason, ref)
        Util.info "api.relaton.org: #{reason}; asking the flavor", key: ref
      end
    end
  end
end
