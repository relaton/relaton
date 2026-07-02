# frozen_string_literal: true

module Relaton
  module Itu
    module Bibliography
      extend self

      # @param refid [Relaton::Itu::Pubid, String] a document reference
      # @return [Relaton::Itu::HitCollection]
      def search(refid)
        if refid.is_a? String
          warn_incorrect_ref(refid)
          refid = Pubid.parse refid
        end
        HitCollection.new(refid).tap(&:search)
      end

      # @param code [String] the ITU standard Code to look up
      # @param year [String] the year the standard was published (optional)
      # @param opts [Hash] options
      # @return [Relaton::Bib::ItemData, nil]
      def get(code, year = nil, opts = {})
        warn_incorrect_ref(code)
        refid = Pubid.parse code
        refid.year ||= year

        ret = itubib_get1(refid)
        return nil if ret.nil?

        ret = ret.to_most_recent_reference unless refid.year || opts[:keep_year]
        ret = ret.to_all_parts if opts[:all_parts]
        ret
      end

      private

      def warn_incorrect_ref(ref)
        if ref =~ /(ITU[\s-]T\s\w)\.(Suppl\.|Annex)\s?(\w?\d+)/
          correct_ref = "#{$~[1]} #{$~[2]} #{$~[3]}"
          Util.info "Incorrect reference: `#{ref}`, the reference should be: `#{correct_ref}`"
        end
      end

      def fetch_ref_err(refid, missed_years)
        Util.info "Not found.", key: refid.to_s
        if missed_years.any?
          plural = missed_years.size > 1 ? "s" : ""
          Util.info "There was no match for `#{refid.year}` year, though there were matches " \
                    "found for `#{missed_years.join('`, `')}` year#{plural}.", key: refid.to_s
        end
        nil
      end

      def search_filter(refid)
        result = search(refid)
        result.select do |i|
          next true unless i.hit[:code]

          pubid = Pubid.parse i.hit[:code]
          refid.===(pubid, [:year])
        end
      end

      def isobib_results_filter(result, refid)
        missed_years = []
        result.each do |r|
          /\((?:\d{2}\/)?(?<pyear>\d{4})\)/ =~ r.hit[:code]
          if !refid.year || refid.year == pyear
            ret = r.item
            return { ret: ret } if ret
          end

          missed_years << pyear
        end
        { years: missed_years }
      end

      def itubib_get1(refid)
        result = search_filter(refid) || return
        ret = isobib_results_filter(result, refid)
        if ret[:ret]
          Util.info "Found: `#{ret[:ret].docidentifier.first&.content}`", key: refid.to_s
          ret[:ret]
        else
          fetch_ref_err(refid, ret[:years])
        end
      end
    end
  end
end
