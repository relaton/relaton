module Relaton
  module Xsf
    class Hit < Relaton::Core::Hit
      def item
        return @doc if @doc

        agent = Mechanize.new
        resp = agent.get hit[:url]
        hash = YAML.safe_load resp.body
        hash["fetched"] = Date.today.to_s
        @doc = Relaton::Xsf::Item.from_yaml hash.to_yaml
      rescue StandardError => e
        raise Relaton::RequestError, e.message
      end
    end
  end
end
