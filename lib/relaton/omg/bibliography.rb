# frozen_string_literal: true

module Relaton
  module Omg
    # OMG bibliography module
    module Bibliography
      extend self

      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-omg/main/".freeze

      # @param ref [String, Pubid::Omg::Identifier] the OMG standard reference
      # @return [Relaton::Omg::Item, nil] nil when neither the machine index
      #   nor the live scrape answers
      def search(ref)
        pubid = ref.is_a?(String) ? ::Pubid::Omg::Identifier.parse(ref) : ref
        Util.info "Fetching from Relaton repository ...", key: pubid.to_s
        from_index(pubid) || begin
          # The crawl does not cover every spec (beta-version pages carry no
          # download link), so a machine-index miss falls back to the live
          # scrape. Index transport failures still raise — they are not
          # misses.
          Util.info "Not in the machine index; scraping www.omg.org ...", key: pubid.to_s
          Scraper.scrape_page ref
        end
      end

      # The machine index on the Pages site (relaton#206): the consumer reads
      # the published index-v2 (whole-index mode — the manifest publishes no
      # shards) and fetches the document from the data repo.
      #
      # @param pubid [Pubid::Omg::Identifier]
      # @return [Relaton::Omg::Item, nil]
      def from_index(pubid)
        row = index.search(pubid).min_by { |r| r[:id].version.to_s }
        return unless row

        uri = URI("#{ENDPOINT}#{row[:file]}")
        resp = Net::HTTP.get_response uri
        unless resp.code == "200"
          raise Relaton::RequestError, "Could not access #{uri}: HTTP #{resp.code}"
        end

        Relaton::Omg::Item.from_yaml resp.body
      end

      # @return [Relaton::Index::Type]
      def index
        Relaton::Index.find_or_create(
          :omg, pages_url: PAGES_URL, pubid_class: ::Pubid::Omg::Identifier
        )
      end

      # @param ref [String, Pubid::Omg::Identifier] the OMG standard reference
      # @param year [String] the year the standard was published (optional)
      # @param opts [Hash] options
      # @return [Relaton::Omg::Item]
      def get(ref, _year = nil, _opts = {})
        Util.info "Fetching from www.omg.org ...", key: ref.to_s
        result = search ref
        if result
          Util.info "Found: `#{result.docidentifier.first.content}`", key: ref.to_s
        else
          Util.info "Not found.", key: ref.to_s
        end
        result
      end
    end
  end
end
