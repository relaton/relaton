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
      def initialize(agent, idrec, imp)
        @agent = agent
        @idrec = idrec
        @imp = imp
      end

      private

      attr_reader :agent, :idrec, :imp
    end
  end
end
