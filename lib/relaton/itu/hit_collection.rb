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
        index = Relaton::Index.find_or_create :itu, url: "#{GH_ITU_R}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml"
        row = index.search(ref.to_ref).max_by { |i| i[:id] }
        return unless row

        url = "#{GH_ITU_R}#{row[:file]}"
        resp = agent.get url
        return if resp.code == "404"

        item = Item.from_yaml(resp.body).tap { |i| i.fetched = Date.today.to_s }
        hit = Hit.new({ url: url, ref: ref }, self)
        hit.item = item
        @array = [hit]
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
