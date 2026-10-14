# frozen_string_literal: true

module Relaton
  module Evs
    # Page of hit collection.
    class HitCollection < Relaton::Core::HitCollection
      DOMAIN = "https://www.evs.ee"

      def search
        @array = hits
        self
      end

      def agent
        @agent ||= Mechanize.new.tap { |a| a.user_agent_alias = "Mac Safari" }
      end

      def select!(&block)
        @array.select!(&block)
        self
      end

      private

      #
      # The catalogue URL is the printed reference slugified
      # (`EVS-EN 18216:2026` -> /en/evs-en-18216-2026), so the search is a
      # direct probe: the product page exists iff the reference denotes a
      # published document. A miss redirects to /page-not-found, which is no
      # hit. A reference carrying the `et` language code probes the Estonian
      # locale, which serves the Estonian-language product.
      #
      # @return [Array<Relaton::Evs::Hit>]
      #
      def hits
        page = agent.get url
        return [] if page.uri.to_s.include? "page-not-found"

        [Hit.new({ code: code, url: page.uri.to_s }, self)]
      rescue Mechanize::ResponseCodeError
        []
      end

      def url
        "#{DOMAIN}/#{locale}/#{slug}"
      end

      def locale
        query_pubid&.language == "et" ? "et" : "en"
      end

      # The hit's code is the reference as queried, minus the "(all parts)"
      # marker: `Hit#pubid` parses it back, and the filter `query === hit.pubid`
      # needs the language code ON the hit for a language-carrying query to
      # match its own record. The slug derivation strips the language code
      # separately — the catalogue URL does not carry it.
      def code
        ref.to_s.sub(/\s+\(all parts\)\z/, "")
      end

      def slug
        code.sub(/\s+(et-en|et|en)\z/, "")
            .downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      end

      def query_pubid
        Bibliography.parse code
      rescue StandardError
        nil
      end
    end
  end
end
