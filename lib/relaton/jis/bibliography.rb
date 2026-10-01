# frozen_string_literal: true

module Relaton
  module Jis
    module Bibliography
      extend self

      #
      # Search JIS by reference, returning the full candidate collection.
      #
      # The reference is parsed into a {Pubid::Jis::Identifier} and matched
      # against the pubid-based `index-v2` via {HitCollection}. Candidates share
      # the reference's series and number (a supplement is filed under its base
      # number), so an edition and its amendments are returned together.
      #
      # @param [String, Pubid::Jis::Identifier] ref JIS document reference; a
      #   pubid is never mutated
      # @param [String, nil] year JIS document year
      #
      # @return [Relaton::Jis::HitCollection] search result
      #
      # @raise [Pubid::Errors::ParseError] when the reference is not a JIS
      #   identifier, so a malformed reference is not reported as "not found"
      #
      def search(ref, year = nil)
        pubid = ref.is_a?(String) ? ::Pubid::Jis::Identifier.parse(ref) : ref
        if year && pubid.year.nil?
          # Copy first: a caller's pubid is also its Db cache key.
          pubid = pubid.class.from_hash(pubid.to_hash)
          pubid.year = year.to_i
        end
        HitCollection.new pubid
      end

      #
      # Get JIS document by reference
      #
      # @param [String, Pubid::Jis::Identifier] ref JIS document reference, or
      #   the parse that Relaton::Db routed with (relaton#205)
      # @param [String, nil] year JIS document year
      # @param [Hash] opts options
      # @option opts [Boolean] :all_parts return all parts of document
      #
      # @return [Relaton::Jis::Item, nil] JIS document
      #
      # @raise [Pubid::Errors::ParseError] when the reference is not a JIS
      #   identifier
      #
      def get(ref, year = nil, opts = {}) # rubocop:disable Metrics/AbcSize
        if ref.is_a?(String)
          query = ref.sub(/\s\((all parts|規格群)\)/, "")
          opts[:all_parts] ||= !$1.nil?
        else
          opts[:all_parts] ||= ref.all_parts?
          query = ref.all_parts? ? ref.identifiers.first : ref
        end
        Util.info "Fetching from webdesk.jsa.or.jp ...", key: ref.to_s
        hits = search(query, year)
        result = opts[:all_parts] ? hits.find_all_parts : hits.find
        if result.is_a? Bib::ItemData
          Util.info "Found: `#{result.docidentifier[0].content}`", key: ref.to_s
          return result
        end
        hint result, ref.to_s, year
      end

      #
      # Log hint message
      #
      # @param [Array] result search result (missed edition years)
      # @param [String] ref reference to search
      # @param [String, nil] year year to search
      #
      def hint(result, ref, year)
        Util.info "Not found.", key: ref
        if result&.any?
          Util.info "TIP: No match for edition year `#{year}`, but " \
                    "matches exist for `#{result.uniq.join('`, `')}`.", key: ref
        end
        nil
      end
    end
  end
end
