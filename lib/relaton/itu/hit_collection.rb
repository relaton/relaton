# frozen_string_literal: true

require_relative "hit"

module Relaton
  module Itu
    # Page of hit collection.
    class HitCollection < Relaton::Core::HitCollection
      DOMAIN = "https://www.itu.int"
      GH_ITU_R = "https://raw.githubusercontent.com/relaton/relaton-data-itu-r/refs/heads/v2/"

      def search
        case ref.to_ref
        when /^(ITU-T|ITU-R\sRR)/
          request_search
        when /^ITU-R\s/
          request_document
        end
      rescue Mechanize::ResponseCodeError, SocketError, Timeout::Error, Errno::ECONNRESET,
              EOFError, Net::ProtocolError, OpenSSL::SSL::SSLError => e
        raise Relaton::RequestError, "Could not access #{ref.to_ref}: #{e.message}"
      end

      def agent
        @agent ||= Mechanize.new.tap { |agent| agent.user_agent_alias = "Mac Safari" }
      end

      private

      def request_search
        Util.info "Fetching from www.itu.int ...", key: ref.to_s
        url = "#{DOMAIN}/net4/ITU-T/search/GlobalSearch/RunSearch"
        data = { json: params.to_json }
        resp = agent.post url, data
        @array = hits JSON.parse(resp.body)
      end

      def request_document # rubocop:todo Metrics/MethodLength, Metrics/AbcSize
        Util.info "Fetching from Relaton repository ...", key: ref.to_s
        index = Relaton::Index.find_or_create :itu, url: "#{GH_ITU_R}#{INDEXFILE}.zip",
                                                     file: "#{INDEXFILE}.yaml",
                                                     pubid_class: ::Pubid::Itu::Identifier
        # Pass the reference's parsed pubid (not a String) so Relaton::Index can
        # narrow candidates by document number before the block; `part_match?`
        # then matches every edition when the reference omits the part and the
        # exact edition when it names one. Rows are Pubid::Itu objects (not
        # Comparable), so rank by the numeric edition in `code.parts` (`["3"]` → 3)
        # to return the latest — index order isn't by edition.
        pubid = pubid_ref
        row = index.search(pubid) { |i| part_match?(pubid, i[:id]) }
          .max_by { |i| i[:id].code&.parts&.last.to_i }
        return unless row

        url = "#{GH_ITU_R}#{row[:file]}"
        resp = agent.get url
        return if resp.code == "404"

        item = Item.from_yaml(resp.body).tap { |i| i.fetched = Date.today.to_s }
        hit = Hit.new({ url: url, ref: ref }, self)
        hit.item = item
        @array = [hit]
      end

      # Parse the reference into a Pubid::Itu identifier for the index lookup. A
      # ref pubid can't parse raises (a `Pubid`/`Parslet` error) and propagates to
      # the caller (relaton-cli / API callers rescue it), mirroring the ETSI
      # flavor — the consumer no longer degrades to a raw-string substring search.
      #
      # @return [::Pubid::Itu::Identifier]
      def pubid_ref
        ::Pubid::Itu.parse ref.to_ref
      end

      # Does an index row's id match the reference? When the reference omits the
      # part/edition (a bare `ITU-R P.838`), every edition of that exact document
      # matches — "search all parts"; when it names a part (`ITU-R P.838-2`), only
      # that edition matches. Delegates to pubid's structured `matches?`, ignoring
      # `:parts` only when the reference omits the part — so a bare `ITU-R M.1`
      # does not match `ITU-R M.10` (a different document number) and `-1` differs
      # from `-10`, without the local `-`-separator anchor. Mirrors the ETSI
      # flavor's `Bibliography#best_match`. Both ids are `Pubid::Itu` identifiers.
      #
      # @param pubid [::Pubid::Itu::Identifier] the reference
      # @param id [::Pubid::Itu::Identifier] an index row's id
      # @return [Boolean]
      def part_match?(pubid, id)
        ignore = pubid.code&.parts.to_a.empty? ? %i[parts] : []
        pubid.matches?(id, ignore: ignore)
      end

      # @return [String]
      def group
        @group ||= case ref.to_ref
                   when %r{OB|Operational Bulletin}, %r{^ITU-R\sRR}
                     "Publications"
                   when %r{^ITU-T} then "Recommendations"
                   end
      end

      # @return [Hash]
      def params # rubocop:disable Metrics/MethodLength
        input = ref.dup
        input.year = nil
        {
          "Input" => input.to_s,
          "Start" => 0,
          "Rows" => 20,
          "SortBy" => "RELEVANCE",
          "ExactPhrase" => false,
          "CollectionName" => "General",
          "CollectionGroup" => group,
          "Sector" => ref.to_ref.match(/(?<=^ITU-)\w/).to_s.downcase,
          "Criterias" => [{
            "Name" => "Search in",
            "Criterias" => [
              {
                "Selected" => false,
                "Value" => "",
                "Label" => "Name",
                "Target" => "/name_s",
                "TypeName" => "CHECKBOX",
                "GetCriteriaType" => 0,
              },
              {
                "Selected" => false,
                "Value" => "",
                "Label" => "Short description",
                "Target" => "/short_description_s",
                "TypeName" => "CHECKBOX",
                "GetCriteriaType" => 0,
              },
              {
                "Selected" => false,
                "Value" => "",
                "Label" => "File content",
                "Target" => "/file",
                "TypeName" => "CHECKBOX",
                "GetCriteriaType" => 0,
              },
            ],
            "ShowCheckbox" => true,
            "Selected" => false,
          }],
          "Topics" => "",
          "ClientData" => {},
          "Language" => "en",
          "SearchType" => "All",
        }
      end

      # @param data [Hash]
      # @return [Array<Relaton::Itu::Hit>]
      def hits(data)
        data["results"].map do |h|
          code  = h["Media"]["Name"]
          title = h["Title"]
          url   = "#{DOMAIN}#{h['Redirection']}"
          type  = h["Collection"]["Group"].downcase[0...-1]
          Hit.new({ code: code, title: title, url: url, type: type }, self)
        end
      end
    end
  end
end
