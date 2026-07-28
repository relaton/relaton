require_relative "../jcgm"
require_relative "meetings_parser"

module Relaton::Jcgm
  # Harvests the JCGM **meeting proceedings** from the `jcgm/meetings-{en,fr}`
  # dirs of a local checkout of metanorma/bipm-data-outcomes, writing one Relaton
  # YAML per meeting and indexing each by its `Pubid::Jcgm` identifier.
  #
  # The curated guide/GUM/VIM records are **not** harvested here: they are
  # hand-maintained YAMLs that live in the data repo's own `static/` dir, so the
  # data repo's `crawler.rb` indexes them (like relaton-data-bipm's crawler does)
  # by looping `static/**` and calling the public, guarded {#add_to_index} —
  # keeping the "which static files" policy in the data repo while the guarded,
  # sorted, `_type: pubid:jcgm:*` indexing mechanism stays here.
  class DataFetcher < Relaton::Core::DataFetcher
    attr_reader :output, :format, :ext, :files, :errors

    def index
      @index ||= Relaton::Index.find_or_create(
        :jcgm, file: "#{INDEXFILE}.yaml", pubid_class: ::Pubid::Jcgm::Identifier
      )
    end

    def log_error(msg) = Util.error msg

    #
    # @param [String] source dataset name ("bipm-data-outcomes")
    #
    def fetch(source)
      MeetingsParser.parse(self) if source == "bipm-data-outcomes"
      index.save
      report_errors
    end

    #
    # Save document to file
    #
    # @param [String] path Path to file
    # @param [Relaton::Jcgm::ItemData] item document to save
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

    #
    # Index a document by its pubid. Guarded defensively: a docnumber the
    # `Pubid::Jcgm` grammar can't parse is skipped with a warning rather than
    # allowed to corrupt the whole index (`Relaton::Index` rejects an index if a
    # single row fails to deserialize). All current JCGM records parse on pubid
    # main; the guard protects against a future malformed record.
    #
    # Public so the data repo's crawler can index its curated `static/` guides
    # through the same guarded, sorted, pubid-backed path the meetings use.
    #
    # @param [String] docnumber the record's docnumber (e.g. "JCGM 17th Meeting (2012)")
    # @param [String] path repo-relative path to the YAML file
    #
    def add_to_index(docnumber, path)
      # Store the Pubid::Jcgm identifier object (not its hash): with pubid_class
      # set, Relaton::Index then sorts the index by id number on save and
      # serializes each id to its `_type: pubid:jcgm:*` hash, so the published
      # index is already sorted (no "not sorted by id number" warning on fetch).
      index.add_or_update ::Pubid::Jcgm.parse(docnumber), path
    rescue StandardError => e
      Util.warn "Skipping index entry for `#{docnumber}` (#{path}): #{e.message}"
    end

    def to_xml(item) = item.to_xml bibdata: true

    def to_yaml(item) = item.to_yaml

    def to_bibxml(item) = item.to_rfcxml
  end
end
