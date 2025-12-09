# frozen_string_literal: true

module Relaton
  module Cen
    # Page of hit collection.
    class HitCollection < Relaton::Core::HitCollection
      DOMAIN = "https://standards.cencenelec.eu"


      # @param ref [String]
      # @param year [String]
      # def initialize(ref, year = nil) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
      #   super ref, year
      def search
        if !ref || ref.empty?
          @array = []
          return
        end

        redirect_page = agent.get DOMAIN
        redirect_url = redirect_page.body.slice(/(?<=follow the <a href=')#{DOMAIN}[^']+/)
        search_page = agent.get redirect_url
        form = search_page.at "//form[@id='wwvFlowForm']"
        form_data = req_body(form)
        resp = agent.post form[:action], form_data.join("&")
        @array = hits resp
        sort
      end

      private

      def agent
        @agent ||= Mechanize.new.tap { |a| a.user_agent_alias = "Mac Safari" }
      end

      def req_body(form)
        body_array = [p_json(form)]
        skip_inputs = %w[f11 essentialCookies]
        form.xpath(".//input[@name]").each_with_object(body_array) do |f, acc|
          next if f[:name].empty? || skip_inputs.include?(f[:name])

          val = case f[:value]
                when "LANGUAGE_LIST" then 0
                when "STAND_REF" then CGI.escape(ref)
                else
                  case f[:name]
                  when "p_request" then "S1-S2-S3-S4-S5-S6-S7-CEN-CLC-"
                  when "f10" then ""
                  else f[:value]
                  end
                end
          acc << (f[:name] == "f10" ? "f10=#{f[:value]}&f11=#{val}" : "#{f[:name]}=#{val}")
        end
      end

      def p_json(form)
        salt = form.at(".//input[@id='pSalt']")[:value]
        protected = form.at(".//input[@id='pPageItemsProtected']")[:value]
        row_version = form.at(".//input[@id='pPageItemsRowVersion']")[:value]
        checksums = JSON.parse form.at(".//input[@id='pPageFormRegionChecksums']")[:value]
        "p_json=" + URI.encode_www_form_component({
          salt: salt,
          pageItems: {
            itemsToSubmit: [],
            protected: protected,
            rowVersion: row_version,
            formRegionChecksums: checksums
          }
        }.to_json)
      end

      def sort
        @array.sort! do |a, b|
          ap = Bibliography.code_to_parts a.hit[:code]
          bp = Bibliography.code_to_parts b.hit[:code]
          s = ap[:code] <=> bp[:code]
          s = ap[:part].to_s <=> bp[:part].to_s if s.zero?
          s = bp[:year].to_s <=> ap[:year].to_s if s.zero?
          s = ap[:amd].to_s <=> bp[:amd].to_s if s.zero?
          s = ap[:amy].to_s <=> bp[:amy].to_s if s.zero?
          s = ap[:ac].to_s <=> bp[:ac].to_s if s.zero?
          s
        end
      end

      # @param resp [Mechanize::Page]
      # @return [Array<RelatonCen::Hit>]
      def hits(resp)
        resp.xpath("//table[@class='dashlist']/tbody/tr/td[2]").map do |h|
          ref = h.at("strong/a")
          code = ref.text.strip
          url = ref[:href]
          Hit.new({ code: code, url: url }, self)
        end
      end
    end
  end
end
