require_relative "recommendation_fields"

module Relaton
  module Itu
    # Live-lookup ITU-T Recommendation parser. All field extraction lives in the
    # shared RecommendationFields module (reused by the offline DataParserT
    # harvester); this class only binds the module's `agent`/`idrec`/`imp` hooks.
    class RecommendationParser
      include RecommendationFields

      # @param agent [Mechanize] the HTTP agent (was a Hit before decoupling)
      # @param idrec [String, Integer] the recommendation record id
      # @param imp [Boolean] Implementers' Guide flag
      # @param cache [#fetch, #warm] cross-row cache for the family-invariant
      #   endpoints. Defaults to NullCache, i.e. off — only the offline
      #   harvester passes a real one, so the live lookup path keeps exactly the
      #   behaviour and the request count it had before the cache existed.
      def initialize(agent, idrec, imp, cache: NullCache.instance)
        @agent = agent
        @idrec = idrec
        @imp = imp
        @cache = cache
      end

      private

      attr_reader :agent, :idrec, :imp, :cache
    end
  end
end
