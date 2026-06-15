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
      # @param [String] code JIS document code
      # @param [String, nil] year JIS document year
      #
      # @return [Relaton::Jis::HitCollection, nil] search result, or nil when
      #   the reference cannot be parsed
      #
      def search(code, year = nil)
        pubid = ::Pubid::Jis::Identifier.parse code
        pubid.year ||= year.to_i if year
        HitCollection.new pubid
      rescue StandardError => e
        Util.warn "Unable to parse `#{code}` with pubid: #{e.message}"
        nil
      end

      #
      # Get JIS document by reference
      #
      # @param [String] ref JIS document reference
      # @param [String, nil] year JIS document year
      # @param [Hash] opts options
      # @option opts [Boolean] :all_parts return all parts of document
      #
      # @return [Relaton::Jis::Item, nil] JIS document
      #
      def get(ref, year = nil, opts = {}) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        code = ref.sub(/\s\((all parts|規格群)\)/, "")
        opts[:all_parts] ||= !$1.nil?
        Util.info "Fetching from webdesk.jsa.or.jp ...", key: ref
        hits = search(code, year)
        unless hits
          hint [], ref, year
          return
        end
        result = opts[:all_parts] ? hits.find_all_parts : hits.find
        if result.is_a? Bib::ItemData
          Util.info "Found: `#{result.docidentifier[0].content}`", key: ref
          return result
        end
        hint result, ref, year
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
