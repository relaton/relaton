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
        @array.sort_by! { |hit| sort_key hit }
        self
      end

      #
      # The order the `code_to_parts` comparison gave, read from pubid instead:
      # the document family ascending, then the part ascending with a part-less
      # hit first, then the year DESCENDING with a year-less hit last, then the
      # supplement, so a base document precedes its own amendments and
      # corrigenda. A hit pubid cannot parse sorts last.
      #
      # `#root` is the accessor that answers for every form: an adopted norm
      # keeps its number, part and year on the adopted ISO document.
      #
      # @param hit [Relaton::Cen::Hit]
      #
      # @return [Array]
      #
      def sort_key(hit)
        id = hit.pubid
        return [1, "", [], 0, ["", "", ""]] unless id

        root = id.root
        [0, family(id), part_segments(root), -root.year.to_s.to_i,
         supplement_key(id)]
      end

      # The document family: the base document with its part and year dropped,
      # e.g. `EN 13250:2000/A1:2005` -> `EN 13250`. Read from the base document
      # rather than from `#root`, so that `EN ISO 1234` and `CEN ISO/TS 1234`
      # stay apart.
      def family(id)
        id.base_document.exclude(:year, :part, :subpart).to_s
      end

      # Part segments as integers, so `-10` sorts after `-2`. pubid holds a
      # sub-part inside `part` (`61375-2-3` gives `"2-3"`).
      def part_segments(root)
        root.part.to_s.split("-").map(&:to_i)
      end

      def supplement_key(id)
        sup = supplements(id).first
        return ["", "", ""] unless sup

        [sup.supplement_type.to_s, sup.supplement_number.to_s,
         sup.supplement_year.to_s]
      end

      # A consolidated identifier (`EN 285:2015+A1:2021`) holds its base
      # document and its supplements in `#identifiers`, and answers none of the
      # supplement accessors itself; an amendment or corrigendum IS the
      # supplement.
      def supplements(id)
        if id.respond_to? :identifiers
          id.identifiers.drop(1)
        elsif id.respond_to? :supplement_type
          [id]
        else
          []
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
