module Relaton
  module Xsf
    class HitCollection < Relaton::Core::HitCollection
      GHDATA_URL = "https://raw.githubusercontent.com/relaton/relaton-data-xsf/v2/".freeze

      def search
        @array = index.search(ref).sort_by { |hit| hit[:id] }.map do |row|
          Hit.new url: "#{GHDATA_URL}#{row[:file]}"
        end
        self
      rescue StandardError => e
        raise Relaton::RequestError, e.message
      end

      def index
        @index ||= Relaton::Index.find_or_create(
          :xsf,
          url: "#{GHDATA_URL}#{INDEXFILE}.zip",
          file: "#{INDEXFILE}.yaml",
        )
      end
    end
  end
end
