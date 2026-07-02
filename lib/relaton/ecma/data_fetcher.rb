# frozen_string_literal: true

require "English"
require "mechanize"
require "relaton/core"
require_relative "../ecma"
require_relative "parser_common"
require_relative "page_fetcher"
require_relative "standard_parser"
require_relative "memento_parser"
require_relative "edition_parser"
require_relative "data_parser"

module Relaton
  module Ecma
    class DataFetcher < Core::DataFetcher
      URL = "https://www.ecma-international.org/publications-and-standards/"
      SOURCES = %w[standards technical-reports mementos].freeze

      def index
        @index ||= Relaton::Index.find_or_create :ecma, file: "#{INDEXFILE}.yaml"
      end

      def log_error(msg)
        Util.error msg
      end

      def agent
        @agent ||= Mechanize.new.tap { |a| a.user_agent_alias = Mechanize::AGENT_ALIASES.keys.sample }
      end

      # @param bib [Relaton::Ecma::ItemData]
      def write_file(bib)
        file = filename bib
        if @files.include? file
          Util.warn "Duplicate file #{file}"
        else
          @files << file
          File.write file, serialize(bib), encoding: "UTF-8"
          index.add_or_update index_id(bib), file
        end
      end

      def filename(bib)
        id = bib.docidentifier[0].content
        id += " #{bib.edition.content}" if bib.edition
        locality = locality_with_volume bib
        id += " #{locality.reference_from}" if locality
        output_file id
      end

      def index_id(bib)
        { id: bib.docidentifier[0].content }.tap do |i|
          i[:ed] = bib.edition.content if bib.edition
          locality = locality_with_volume bib
          i[:vol] = locality.reference_from if locality
        end
      end

      def locality_with_volume(bib)
        bib.extent.each do |e|
          locality = e.locality.find { |l| l.type == "volume" }
          return locality if locality
        end
        nil
      end

      def to_xml(bib) = bib.to_xml(bibdata: true)
      def to_yaml(bib) = bib.to_yaml
      def to_bibxml(bib) = bib.to_rfcxml

      # @param hit [Nokogiri::XML::Element]
      def parse_page(hit) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        DataParser.new(hit, @errors).parse.each { |item| write_file item }
      end

      # @param type [String]
      def html_index(type) # rubocop:disable Metrics/MethodLength
        result = agent.get "#{URL}#{type}/"
        # @last_call_time = Time.now
        result.xpath(
          "//li/span[1]/a",
          "//div[contains(@class, 'entry-content-wrapper')][.//a[.='Download']]",
        ).each do |hit|
          parse_page(hit)
        rescue StandardError => e
          Util.error { "#{e.message}\n#{e.backtrace}" }
        end
      end

      #
      # Fetch data from Ecma website.
      #
      # @return [void]
      #
      def fetch(_ = nil)
        SOURCES.each { |source| html_index source }
        index.save
        report_errors
      end
    end
  end
end
