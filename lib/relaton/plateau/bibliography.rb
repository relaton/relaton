module Relaton
  module Plateau
    module Bibliography
      extend self

      # @param ref [String, Pubid::Plateau::Identifier] the reference, or the
      #   parse that Relaton::Db routed with (relaton#205)
      def search(ref)
        HitCollection.new(ref).find
      end

      # Only a transport failure is rescued, and it becomes the
      # Relaton::RequestError that Relaton::Db retries. Anything else keeps
      # its own class: an unrecognized reference raises Pubid::Errors::ParseError
      # (relaton-cli reports it), and a bug keeps its backtrace.
      def get(ref, _year = nil, _opts = {}) # rubocop:disable Metrics/MethodLength
        Util.info "Fetching ...", key: ref.to_s
        result = search(ref).fetch_doc
        if result
          Util.info "Found `#{result.docidentifier.first.content}`", key: ref.to_s
          result
        else
          Util.warn "Not found.", key: ref.to_s
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
