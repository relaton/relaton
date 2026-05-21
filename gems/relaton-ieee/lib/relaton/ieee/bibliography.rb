module Relaton
  module Ieee
    class Bibliography
      GH_URL = "https://raw.githubusercontent.com/relaton/relaton-data-ieee/refs/heads/v2/".freeze

      class << self
        #
        # Search IEEE bibliography item by reference.
        #
        # @param code [String]
        #
        # @return [Relaton::Ieee::ItemData, nil]
        #
        def search(code) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          # ref = code.sub(/Std\s/i, "") # .gsub(/[\s,:\/]/, "_").squeeze("_").upcase
          index = Relaton::Index.find_or_create :ieee, url: "#{GH_URL}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml"
          row = index.search(code).min_by { |r| r[:id] }
          return unless row

          resp = Faraday.get "#{GH_URL}#{row[:file]}"
          return unless resp.status == 200

          Item.from_yaml(resp.body).tap { |item| item.fetched = Date.today.to_s }
        rescue Faraday::ConnectionFailed
          raise Relaton::RequestError, "Could not access #{GH_URL}"
        end

        #
        # Get IEEE bibliography item by reference.
        #
        # @param code [String] the IEEE standard Code to look up (e..g "528-2019")
        # @param year [String] the year the standard was published (optional)
        # @param opts [Hash] options
        #
        # @return [Relaton::Ieee::ItemData, nil]
        #
        def get(code, _year = nil, _opts = {}) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          Util.info "Fetching from Relaton repository ...", key: code
          item = search(code)
          if item
            Util.info "Found: `#{item.docidentifier.first.content}`", key: code
            item
          else
            Util.info "Not found.", key: code
            nil
          end
        end
      end
    end
  end
end
