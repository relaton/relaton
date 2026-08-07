require_relative "../bipm"
require_relative "data_outcomes_parser"
require_relative "si_brochure_parser"
require_relative "rawdata_bipm_metrologia/fetcher"

module Relaton::Bipm
  class DataFetcher < Relaton::Core::DataFetcher
    attr_reader :output, :format, :ext, :files, :index, :errors

    def index
      @index ||= Relaton::Index.find_or_create(
        :bipm, file: "#{INDEXFILE}.yaml", pubid_class: ::Pubid::Bipm::Identifier
      )
    end

    def log_error(msg)
      Util.error msg
    end

    #
    # Index a document by its pubid. Guarded defensively: a docnumber the
    # `Pubid::Bipm` grammar can't parse (a legacy/inconsistent id, or a
    # wrong-flavor orphan) is skipped with a warning rather than allowed to
    # corrupt the whole index (`Relaton::Index` rejects an index if a single
    # row fails to deserialize). Mirrors `Relaton::Jcgm::DataFetcher#add_to_index`.
    #
    # Public so `relaton-data-bipm`'s crawler can index its curated `static/`
    # docs through the same guarded, sorted, `_type: pubid:bipm:*` path.
    #
    # @param [String] docnumber the record's primary docidentifier / docnumber
    # @param [String] path repo-relative path to the YAML file
    #
    def add_to_index(docnumber, path)
      # Store the Pubid::Bipm identifier object (not a hash): with pubid_class
      # set, Relaton::Index sorts the index by id number on save and serializes
      # each id to its `_type: pubid:bipm:*` hash, so the published index is
      # already sorted (no "not sorted by id number" warning on consumer fetch).
      index.add_or_update ::Pubid::Bipm.parse(docnumber), path
    rescue StandardError => e
      Util.warn "Skipping index entry for `#{docnumber}` (#{path}): #{e.message}"
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
      report_errors
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

    def to_xml(item) = item.to_xml bibdata: true

    def to_yaml(item) = item.to_yaml

    def to_bibxml(item) = item.to_rfcxml
  end
end
