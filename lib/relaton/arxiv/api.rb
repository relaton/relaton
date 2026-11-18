module Relaton
  module Arxiv
    #
    # The arXiv API (https://info.arxiv.org/help/api/). One `id_list` query
    # answers one Atom feed; an unversioned id answers the latest version.
    #
    module Api
      extend self

      ENDPOINT = "https://export.arxiv.org/api/query".freeze

      # Transport failures, raised as `Relaton::RequestError` so that
      # `Db#net_retry` retries them (as `Relaton::Doi::Http` does).
      NETWORK_ERRORS = [
        SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError,
        EOFError, IOError, Net::ProtocolError
      ].freeze

      #
      # The Atom feed for an arXiv id. A feed with no entry is how arXiv
      # answers an id it does not have, so only a transport failure raises.
      #
      # @param id [String] the bare id, `2301.00001v1` or `hep-th/9901001`
      # @return [String] the Atom XML
      # @raise [Relaton::RequestError] a non-200 answer or a network failure
      #
      def feed(id)
        uri = URI ENDPOINT
        uri.query = URI.encode_www_form(id_list: id)
        response = Net::HTTP.get_response uri
        unless response.is_a? Net::HTTPSuccess
          raise Relaton::RequestError,
                "arXiv API answered #{response.code} for #{id}"
        end

        response.body.dup.force_encoding Encoding::UTF_8
      rescue *NETWORK_ERRORS => e
        raise Relaton::RequestError, "arXiv API: #{e.class}: #{e.message}"
      end
    end
  end
end
