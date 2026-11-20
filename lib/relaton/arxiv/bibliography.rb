module Relaton
  module Arxiv
    #
    # Fetch an arXiv e-print by its id.
    #
    module Bibliography
      extend self

      #
      # @param ref [String, Pubid::Arxiv::Identifier] `arXiv:2301.00001v1`,
      #   `arxiv:hep-th/9901001`; a parsed pubid is not mutated
      # @param _year [String, nil] ignored: the id carries its year
      # @param _opts [Hash]
      # @return [Relaton::Bib::ItemData, nil]
      # @raise [Relaton::RequestError] the arXiv API did not answer
      #
      def get(ref, _year = nil, _opts = {})
        pubid = ref.is_a?(::Pubid::Arxiv::Identifier) ? ref : parse(ref)
        unless pubid
          Util.info "Not an arXiv identifier.", key: ref.to_s
          return
        end

        Util.info "Fetching from arXiv ...", key: pubid.to_s
        item = Parser.parse Api.feed(pubid.to_s(with_publisher: false))
        if item
          Util.info "Found: `#{item.docidentifier.first.content}`", key: pubid.to_s
        else
          Util.info "Not found.", key: pubid.to_s
        end
        item
      end

      #
      # @param ref [String]
      # @return [Pubid::Arxiv::Identifier, nil]
      #
      def parse(ref)
        ::Pubid::Arxiv.parse ref.strip
      rescue ArgumentError, ::Pubid::Errors::Error
        nil
      end
    end
  end
end
