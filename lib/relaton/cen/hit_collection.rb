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
          return self
        end

        redirect_page = agent.get DOMAIN
        redirect_url = redirect_page.body.slice(/(?<=follow the <a href=')#{DOMAIN}[^']+/)
        search_page = agent.get redirect_url
        form = search_page.form_with(id: "wwvFlowForm")
        ref_field = form.field_with(id: "STAND_REF")
        ref_field.value = ref
        resp = agent.submit form
        @array = hits resp
        sort
      end

      def agent
        @agent ||= Mechanize.new.tap { |a| a.user_agent_alias = "Mac Safari" }
      end

      def select!(&block)
        @array.select!(&block)
        self
      end

      private

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
        self
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
