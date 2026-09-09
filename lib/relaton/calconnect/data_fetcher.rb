# frozen_string_literal:true

require "json"
require "mechanize"
require "relaton/core"
require "relaton/index"
# The flavor top-level, for INDEXFILE and ::Pubid::Calconnect::Identifier.
# `relaton-data-calconnect`'s crawler requires THIS file and nothing else, so
# without it `#index` NameErrors on the very first document. (The ECMA form;
# the same invariant the processor's `remove_index_file` follows.)
require_relative "../calconnect"
require_relative "scraper"
require_relative "util"

module Relaton::Calconnect
  #
  # Relaton-calconnect data fetcher
  #
  class DataFetcher < Relaton::Core::DataFetcher
    ENDPOINT = "https://standards.calconnect.org/cc/index.json"

    def etagfile
      @etagfile ||= File.join @output, "etag.txt"
    end

    # The pubid `index-v2` this crawl builds.
    #
    # `pubid_class:` is required on the producer too: `FileIO#save` calls
    # `to_hash` only for instances of it, so without it the crawl writes
    # v1-shaped rows under a v2 name, silently, and the consumer then rejects
    # the whole index. Memoized with `||=` — re-creating the Type on every call
    # evicts the pooled entry a suite (or a sibling call site) set up.
    def index
      @index ||= Relaton::Index.find_or_create(
        :CC, file: "#{INDEXFILE}.yaml",
             pubid_class: ::Pubid::Calconnect::Identifier
      )
    end

    def log_error(msg)
      Util.error msg
    end

    def agent
      @agent ||= Mechanize.new
    end

    #
    # fetch data form server and save it to file.
    #
    def fetch(_source = nil) # rubocop:disable Metrics/AbcSize
      agent.request_headers["If-None-Match"] = etag if etag
      resp = agent.get(ENDPOINT)
      # 304 Not Modified — nothing changed since the last fetch
      return if resp.code == "304"

      data = JSON.parse resp.body
      all_success = true
      Array(data["documents"]).each { |doc| all_success &&= parse_page doc }
      self.etag = resp.response["etag"] if all_success
      index.save
      report_errors
    end

    private

    #
    # Parse document and write it to file
    #
    # @param [Hash] doc
    #
    def parse_page(doc)
      bib = Scraper.new(@errors).parse_page doc
      write_doc doc["id"], bib
      true
    rescue StandardError => e
      Util.warn "Document: #{doc['id']}"
      Util.warn e.message
      Util.warn e.backtrace[0..5].join("\n")
      false
    end

    def write_doc(slug, bib) # rubocop:disable Metrics/MethodLength
      # Distinct slugs can sanitize to one filename; take a path of our own
      # rather than overwriting the other document (Core#unique_output_file).
      file = unique_output_file slug
      if @files.include? file
        # Same reserved path == same slug: a genuine duplicate. Checked FIRST,
        # because a disambiguated path stays != output_file forever.
        Util.warn "#{file} exist"
      elsif file != output_file(slug)
        Util.warn "#{output_file slug} exist; writing #{file} instead"
      end
      @files << file
      # Write first, index second: an id pubid rejects is skipped from the
      # index, and the document still has to reach disk.
      File.write file, serialize(bib), encoding: "UTF-8"
      add_to_index bib, file
    end

    #
    # Index the document, or record why it could not be indexed.
    #
    # An id pubid cannot rebuild is recorded in `@errors` — the inherited
    # `report_errors` logs a String value as the message, and its GhIssue
    # channel opens a GitHub issue at the end of the crawl — and the row is
    # skipped rather than indexed unparsed: `Relaton::Index` rejects the WHOLE
    # index if a single row fails to deserialize, and its sort calls
    # `.root.number` on every id. The data file is already written by the
    # caller, so the document is unindexed, never lost. (The ECMA/W3C shape.)
    #
    # @param bib [Relaton::Calconnect::ItemData]
    # @param file [String] path the document was written to
    #
    def add_to_index(bib, file)
      id = index_id bib
      return index.add_or_update(id, file) if id

      docid = primary_docid(bib)&.content || file
      @errors[docid.to_s] = "Unparseable primary id `#{docid}` was not indexed (#{file})"
    end

    #
    # The index key: the primary docidentifier's own
    # `Pubid::Calconnect::Identifier`.
    #
    # Taken from the parsed model, never re-parsed from a rendered string, and
    # never mutated — unlike ECMA, the CalConnect index key IS the document's
    # printed id (`CC/DIR 10005:2019`), because pubid renders the publisher by
    # default and the flavor models no edition or volume. There is no
    # index-only component to add and none to strip.
    #
    # It is still **duplicated**, for a different reason than ECMA's: the index
    # holds the object, and `Docidentifier#remove_date!` mutates the identifier
    # in place. Sharing it would let anything that asks a crawled record for its
    # most-recent reference rewrite an already-indexed key, between
    # `add_or_update` and `index.save`, with nothing to show for it.
    #
    # @param bib [Relaton::Calconnect::ItemData]
    # @return [Pubid::Calconnect::Identifier, nil] nil if pubid rejects the docid
    #
    def index_id(bib)
      primary_docid(bib)&.pubid&.dup
    end

    # The docidentifier the index is keyed on — the canonical one
    # (e.g. "CC/DIR 10005:2019"), never the upstream slug used for filenames.
    # Every published record carries exactly one, marked primary; the fallback
    # is for a record that marks none.
    def primary_docid(bib)
      bib.docidentifier.find(&:primary) || bib.docidentifier.first
    end

    def to_yaml(bib) = bib.to_yaml
    def to_xml(bib) = bib.to_xml(bibdata: true)
    def to_bibxml(bib) = bib.to_rfcxml

    #
    # Read ETag from file
    #
    # @return [String, NilClass]
    def etag
      @etag ||= File.exist?(etagfile) ? File.read(etagfile, encoding: "UTF-8") : nil
    end

    #
    # Save ETag to file
    #
    # @param tag [String]
    def etag=(e_tag)
      File.write etagfile, e_tag, encoding: "UTF-8"
    end
  end
end
