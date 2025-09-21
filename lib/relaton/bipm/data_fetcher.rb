require_relative "id_parser"
require_relative "../bipm"
require_relative "data_outcomes_parser"
require_relative "si_brochure_parser"
require_relative "rawdata_bipm_metrologia/fetcher"

module Relaton::Bipm
  class DataFetcher < Relaton::Core::DataFetcher
    attr_reader :output, :format, :ext, :files, :index

    def index
      @index ||= Relaton::Index.find_or_create :bipm, file: Bibliography::INDEX_FILE
    end

    #
    # Fetch bipm-data-outcomes or si-brochure
    #
    # @param [String] source Source name
    #
    def fetch(source)
      case source
      when "bipm-data-outcomes" then DataOutcomesParser.parse(self)
      when "bipm-si-brochure" then SiBrochureParser.parse(self)
      when "rawdata-bipm-metrologia" then RawdataBipmMetrologia::Fetcher.fetch(self)
      end
      index.save
    end

    #
    # Save document to file
    #
    # @param [String] path Path to file
    # @param [RelatonBipm::BipmBibliographicItem] item document to save
    # @param [Boolean, nil] warn_duplicate Warn if document already exists
    #
    def write_file(path, item, warn_duplicate: true)
      content = serialize item
      if @files.include?(path)
        Util.warn "File #{path} already exists" if warn_duplicate
      else
        @files << path
      end
      File.write path, content, encoding: "UTF-8"
    end

    def serialize(item)
      case @format
      when "xml" then item.to_xml bibdata: true
      when "yaml" then item.to_yaml
      # when "bibxml" then item.to_bibxml # not implemented in Relaton::Bib yet
      end
    end
  end
end
