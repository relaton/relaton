# frozen_string_literal: true

require_relative "hit_collection"

# GB bib module.
module Relaton
  module Gb
    # GB entry point class.
    class Bibliography
      class << self
        # rubocop:disable Metrics/MethodLength
        # @param text [Strin] code of standard for search
        # @return [RelatonGb::HitCollection]
        def search(text)
          case text
          when /^(GB|GJ|GS)/
            # Scrape national standards.
            Util.info "Fetching from openstd.samr.gov.cn ...", key: text
            require_relative "gb_scraper"
            GbScraper.scrape_page text
          # when /^ZB/
            # Scrape proffesional.
          # when /^DB/
            # Scrape local standard.
          # when %r{^Q/}
            # Enterprise standard
          when %r{^T/[^\s]{2,6}\s}
            # Scrape social standard.
            Util.info "Fetching from www.ttbz.org.cn ...", key: text
            require_relative "t_scraper"
            TScraper.scrape_page text
          else
            # Scrape sector standard.
            require "relaton/gb/sec_scraper"
            SecScraper.scrape_page text
          end
        end
        # rubocop:enable Metrics/MethodLength

        # @param code [String] the GB standard Code to look up (e..g "GB/T 20223")
        # @param year [String] the year the standard was published (optional)
        # @param opts [Hash] options; restricted to :all_parts if all-parts reference is required
        # @return [Relaton::Gb::ItemData, nil]
        # @raise [Pubid::Errors::ParseError] when the code is not a GB
        #   identifier
        def get(code, year = nil, opts = {})
          require "pubid"
          pubid = ::Pubid::Gb::Identifier.parse(code)
          year = (year || pubid.year)&.to_s
          pubid = pubid.exclude(:year)
          pubid.part = "1" if opts[:all_parts]
          ret = get1(pubid, year, opts)
          return nil if ret.nil?

          ret = ret.to_most_recent_reference unless year
          ret = ret.to_all_parts if opts[:all_parts]
          ret
        end

        private

        # @param pubid [Pubid::Gb::Identifier] the reference without a year
        def fetch_ref_err(pubid, year, missed_years) # rubocop:disable Metrics/MethodLength
          unless missed_years.empty?
            Util.info "(There was no match for `#{year}`, though there " \
                      "were matches found for `#{missed_years.join('`, `')}`.)"
          end
          if pubid.part
            Util.info "The provided document part may not exist, or " \
                      "the document may no longer be published in parts."
          else
            Util.info "If you wanted to cite all document parts for the " \
                      "reference, use `#{pubid} (all parts)`.\nIf the document " \
                      "is not a standard, use its document type abbreviation " \
                      "(TS, TR, PAS, Guide)."
          end
          nil
        end

        # @param pubid [Pubid::Gb::Identifier] the reference without a year
        # @param year [String, nil]
        def get1(pubid, year, _opts)
          # search must include year whenever available
          query = with_year(pubid, year)
          searchcode = query.to_s
          result = search_filter(query) || return
          ret = results_filter(result, year)
          if ret[:ret]
            Util.info "Found: `#{ret[:ret].docidentifier.first.content}`", key: searchcode
            ret[:ret]
          else
            Util.info "Not found.", key: searchcode
            fetch_ref_err(pubid, year, ret[:years])
          end
        end

        # @param pubid [Pubid::Gb::Identifier]
        # @param year [String, nil]
        # @return [Pubid::Gb::Identifier] a copy of pubid that carries the year
        def with_year(pubid, year)
          return pubid unless year

          dated = pubid.exclude
          dated.date = ::Pubid::Components::Date.new(year: year)
          dated
        end

        # Keeps the hits that name the queried document. A query with no year
        # matches every year. A query with no part matches only the part-less
        # document: in GB, `GB/T 20223` and `GB/T 20223.1` are two documents.
        #
        # @param query [Pubid::Gb::Identifier]
        # @return [Relaton::Gb::HitCollection, nil]
        def search_filter(query)
          ignore = query.year ? [] : %i[year]
          result = search(query.to_s)
          result&.select! do |hit|
            hit_pubid = parse_docref(hit.docref)
            hit_pubid && query.matches?(hit_pubid, ignore: ignore)
          end
        end

        # A portal docref is data, so a value pubid cannot read is nil and
        # drops the hit.
        #
        # @param docref [String, nil]
        # @return [Pubid::Gb::Identifier, nil]
        def parse_docref(docref)
          ::Pubid::Gb::Identifier.parse(docref) if docref
        rescue StandardError
          nil
        end

        # Sort through the results from Isobib, fetching them three at a time,
        # and return the first result that matches the code,
        # matches the year (if provided), and which # has a title (amendments do
        # not).
        # Only expects the first page of results to be populated.
        # Does not match corrigenda etc (e.g. ISO 3166-1:2006/Cor 1:2007)
        # If no match, returns any years which caused mismatch, for error
        # reporting
        def results_filter(result, year) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength
          missed_years = []
          result.each_slice(3) do |s| # ISO website only allows 3 connections
            fetch_pages(s, 3).each do |r|
              return { ret: r } if !year

              r.date.select { |d| d.type == "published" }.each do |d|
                return { ret: r } if year.to_i == d.at.to_date.year

                missed_years << d.on(:year)
              end
            end
          end
          { years: missed_years }
        end

        # @param hits [RelatonBib::HitCollection<RelatonBib::Hit>]
        # @param threads [Integer]
        # @return [Array<RelatonBib::GbBibliographicItem>]
        def fetch_pages(hits, threads)
          workers = Core::WorkersPool.new threads
          workers.worker { |w| { i: w[:i], hit: w[:hit].item } }
          hits.each_with_index { |hit, i| workers << { i: i, hit: hit } }
          workers.end
          workers.result.sort_by { |x| x[:i] }.map { |x| x[:hit] }
        end
      end
    end
  end
end
