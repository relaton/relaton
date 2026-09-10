module Relaton
  module Plateau
    module Bibliography
      extend self

      def search(code)
        HitCollection.new(code).find
      end

      # Only a transport failure is rescued, and it becomes the
      # Relaton::RequestError that Relaton::Db retries. Anything else keeps
      # its own class: an unrecognized reference raises Parslet::ParseFailed
      # (relaton-cli reports it), and a bug keeps its backtrace.
      def get(code, _year = nil, _opts = {}) # rubocop:disable Metrics/MethodLength
        Util.info "Fetching ...", key: code
        result = search(code).fetch_doc
        if result
          Util.info "Found `#{result.docidentifier.first.content}`", key: code
          result
        else
          Util.warn "Not found.", key: code
        end
      rescue SocketError, Errno::EINVAL, Errno::ECONNRESET, EOFError,
             Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
             Net::ProtocolError, Net::ReadTimeout, OpenSSL::SSL::SSLError,
             Errno::ETIMEDOUT => e
        raise Relaton::RequestError, e.message
      end
    end
  end
end
