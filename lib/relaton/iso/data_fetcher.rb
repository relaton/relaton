require "fileutils"
require "json"
require "net/http"
require "tmpdir"
require_relative "../iso"
require_relative "data_parser"

module Relaton
  module Iso
    #
    # Fetch ISO documents from the ISO Open Data programme bulk JSONL
    # (see https://www.iso.org/open-data.html) and write each one as a YAML
    # file under `@output`.
    #
    # The upstream feed has no delta API, so any run that proceeds re-downloads
    # and re-ingests the whole feed. There is therefore no value in a partial
    # update: a run either skips entirely or does a full replace. `source` modes
    # (matching the `Relaton::Core::DataFetcher.fetch` arg):
    #
    # * `"iso-open-data"` (default) - skip when the feed's `Last-Modified` is
    #   unchanged; otherwise wipe `@output` + index and rebuild from scratch.
    # * `"iso-open-data-all"` - the same full rebuild, but ignore the
    #   `Last-Modified` short-circuit and always run.
    #
    # Wiping happens here, after the short-circuit decision, so `@output` and the
    # index always mirror the current feed (records that have left it don't
    # linger as stale files or dangling index entries) without risking an empty
    # tree on a skipped run. `#fetch` returns true when it rebuilt, false when
    # it skipped, so callers can chain follow-up work (e.g. the pubid-v1 index).
    #
    class DataFetcher < Core::DataFetcher
      OPEN_DATA_URL = "https://isopublicstorageprod.blob.core.windows.net/" \
                      "opendata/_latest/iso_deliverables_metadata/json/" \
                      "iso_deliverables_metadata.jsonl".freeze
      TC_DATA_URL = "https://isopublicstorageprod.blob.core.windows.net/" \
                    "opendata/_latest/iso_technical_committees/json/" \
                    "iso_technical_committees.jsonl".freeze
      LAST_MODIFIED_FILE = "last_modified.txt".freeze
      MAX_DOWNLOAD_RETRIES = 4
      RETRY_BACKOFF_BASE = 30

      def log_error(msg)
        Util.error msg
      end

      def index
        @index ||= Relaton::Index.find_or_create(
          :iso, file: "#{INDEXFILE}.yaml", pubid_class: ::Pubid::Iso::Identifier,
        )
      end

      def fetch(source = nil)
        @source = source || "iso-open-data"
        @full_refresh = @source == "iso-open-data-all"

        Util.info "Fetching ISO Open Data (mode: #{@source})..."
        last_modified = fetch_last_modified
        return false if up_to_date?(last_modified)

        reset_output
        jsonl_path = download_dataset
        ref_index, amend_index, date_index = build_ref_index(jsonl_path)
        tc_index = build_tc_index
        ingest_records(jsonl_path, ref_index, tc_index, amend_index, date_index)
        merge_static_files

        index.save
        save_last_modified(last_modified)
        report_errors
        true
      rescue StandardError => e
        Util.error "#{e.message}\n#{e.backtrace.join("\n")}"
        raise
      end

      private

      # --- HTTP / state -----------------------------------------------------

      def fetch_last_modified
        uri = URI(OPEN_DATA_URL)
        resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          http.request(Net::HTTP::Head.new(uri.request_uri))
        end
        resp["last-modified"]
      end

      def up_to_date?(last_modified)
        return false if @full_refresh || last_modified.nil?
        return false unless File.exist?(LAST_MODIFIED_FILE)
        return false unless output_populated?

        if File.read(LAST_MODIFIED_FILE, encoding: "UTF-8").strip == last_modified.strip
          Util.info "ISO Open Data is up to date (Last-Modified: #{last_modified}); nothing to do."
          true
        else
          false
        end
      end

      # Guard against an external wipe (or a fresh checkout) — if the YAML tree
      # or the index file is gone, force a refresh instead of trusting
      # `LAST_MODIFIED_FILE`.
      def output_populated?
        return false unless Dir.exist?(@output)
        return false unless File.exist?("#{INDEXFILE}.yaml")

        Dir.children(@output).any? { |f| f.end_with?(".yaml") }
      end

      def save_last_modified(last_modified)
        return unless last_modified

        File.write(LAST_MODIFIED_FILE, last_modified, encoding: "UTF-8")
      end

      # Reset the data tree and the index together so the rebuild is a clean
      # mirror of the feed. Called only after the short-circuit, so a skipped run
      # never strands an empty tree. `Core::DataFetcher.fetch` recreates the
      # directory before ingest writes into it.
      def reset_output
        FileUtils.rm_rf(@output)
        index.remove_all
        FileUtils.mkdir_p(@output)
      end

      def download_dataset
        download_jsonl(OPEN_DATA_URL, "iso_deliverables_metadata.jsonl")
      end

      def download_tc_dataset
        download_jsonl(TC_DATA_URL, "iso_technical_committees.jsonl")
      end

      def download_jsonl(url, filename)
        path = File.join(Dir.tmpdir, filename)
        Util.info "Downloading #{url}..."
        uri = URI(url)
        attempt = 0
        begin
          File.open(path, "wb") do |f|
            Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
              http.request_get(uri.request_uri) do |resp|
                raise "Open Data download failed: HTTP #{resp.code}" unless resp.code == "200"

                resp.read_body { |chunk| f.write(chunk) }
              end
            end
          end
        rescue StandardError => e
          attempt += 1
          raise if attempt > MAX_DOWNLOAD_RETRIES

          delay = RETRY_BACKOFF_BASE * (2**(attempt - 1))
          Util.warn "Download attempt #{attempt}/#{MAX_DOWNLOAD_RETRIES} failed (#{e.message}). Retrying in #{delay}s..."
          sleep delay
          retry
        end
        Util.info "Downloaded #{File.size(path) / 1024 / 1024} MB to #{path}."
        path
      end

      # --- ingestion --------------------------------------------------------

      def build_ref_index(path)
        Util.info "Indexing references and amendments..."
        ref_map = {}
        amend_map = Hash.new { |h, k| h[k] = [] }
        date_map = {}
        File.foreach(path, encoding: "UTF-8") do |line|
          rec = JSON.parse(line)
          id = rec["id"]
          ref = normalize_reference(rec["reference"])
          next unless ref

          ref_map[id] = ref if id
          pub_date = rec["publicationDate"]
          date_map[ref] = pub_date if pub_date && !pub_date.empty?
          if rec["supplementType"] && (base = amend_base(ref))
            amend_map[base] << ref
          end
        rescue JSON::ParserError
          next
        end
        Util.info "Indexed #{ref_map.size} references; " \
                  "#{amend_map.values.sum(&:size)} amendments across #{amend_map.size} bases; " \
                  "#{date_map.size} publication dates."
        [ref_map, amend_map, date_map]
      end

      def amend_base(ref)
        pubid = ::Pubid::Iso::Identifier.parse(ref)
        return nil unless pubid.base_identifier

        pubid.base_identifier.to_s
      rescue StandardError
        nil
      end

      # Open Data emits stub records for deleted/abandoned projects with a
      # "Withdrawn" publisher prefix. They have no publicationDate, no edition,
      # and sit on stage *.98 (deleted). Skip them entirely.
      def normalize_reference(ref)
        return nil if ref.nil? || ref.empty?
        return nil if ref.start_with?("Withdrawn ")

        ref
      end

      def ingestable?(ref)
        !ref.nil? && !ref.empty? && !ref.start_with?("Withdrawn ")
      end

      def build_tc_index
        Util.info "Indexing technical committees..."
        path = download_tc_dataset
        map = {}
        File.foreach(path, encoding: "UTF-8") do |line|
          rec = JSON.parse(line)
          ref = rec["reference"]
          title = rec["title"]
          map[ref] = title if ref && title.is_a?(Hash)
        rescue JSON::ParserError
          next
        end
        Util.info "Indexed #{map.size} committees."
        map
      end

      def ingest_records(path, ref_index, tc_index, amend_index = {}, date_index = {})
        Util.info "Parsing records..."
        count = 0
        File.foreach(path, encoding: "UTF-8") do |line|
          rec = JSON.parse(line)
          next unless ingestable?(rec["reference"])

          fetch_pub(rec, ref_index, tc_index, amend_index, date_index)
          count += 1
          Util.info "Processed #{count} records..." if (count % 5_000).zero?
        rescue StandardError => e
          Util.warn "Failed record `#{rec && rec['reference']}`: #{e.message}"
        end
        Util.info "Finished: #{count} records."
      end

      def fetch_pub(rec, ref_index, tc_index = {}, amend_index = {}, date_index = {})
        doc = DataParser.new(rec, ref_index, @errors, tc_index, amend_index, date_index).parse
        docid = doc.docidentifier.detect(&:primary)
        return unless docid

        file = output_file(docid.content.to_s)
        if File.exist?(file)
          rewrite_with_same_or_newer(doc, docid, file)
        else
          write_file(file, doc, docid)
        end
      end

      def rewrite_with_same_or_newer(doc, docid, file)
        existing = Item.from_yaml(File.read(file, encoding: "UTF-8"))
        if edition_greater?(doc, existing) || replace_substage98?(doc, existing)
          write_file(file, doc, docid)
        elsif @files.include?(file) && !edition_greater?(existing, doc)
          Util.warn "Duplicate file `#{file}` for `#{docid.content}`"
        end
      end

      def edition_greater?(doc, bib)
        doc.edition && bib.edition && doc.edition.content.to_i > bib.edition.content.to_i
      end

      def replace_substage98?(doc, bib)
        doc.edition&.content == bib.edition&.content &&
          (doc.status&.substage&.content != "98" || bib.status&.substage&.content == "98")
      end

      def write_file(file, doc, docid)
        @files << file
        index_primary(docid, file)
        File.write(file, serialize(doc), encoding: "UTF-8")
      end

      # Add a document's primary id to the index. With pubid 2.x every ISO id
      # is expected to parse; if one does not (`docid.pubid` is nil) record it
      # so `report_errors` raises a tracked GitHub issue at the end, and skip
      # the index entry rather than indexing a raw string (which would crash
      # the index sort: `get_id_number` calls `.number` on the id). The data
      # file is still written, so the document is not lost — only unindexed
      # until its id parses.
      def index_primary(docid, file)
        unless docid.pubid
          unparseable_ids << [docid.content.to_s, file]
          return
        end
        index.add_or_update(docid.pubid, file)
      end

      def unparseable_ids
        @unparseable_ids ||= []
      end

      # Surface unparseable primary ids through the shared error-reporting
      # machinery (a "Error fetching documents" GitHub issue in CI) so they are
      # visible and tracked, not silently dropped in the action log. The
      # gh_issue logger channel is registered inside `report_errors`, so emit
      # these at :error after it is set up and before `super` creates the issue.
      def report_errors
        gh_issue
        unparseable_ids.each do |content, file|
          log_error "Unparseable primary id `#{content}` was not indexed (#{file})"
        end
        super
      end

      # --- static merge -----------------------------------------------------

      def merge_static_files
        return unless Dir.exist?("static")

        Dir["static/**/*.yaml"].each do |f|
          item = Item.from_yaml(File.read(f, encoding: "UTF-8"))
          did = item.docidentifier.detect(&:primary)
          next unless did

          index_primary(did, f)
        end
      end

      # --- serialization ---------------------------------------------------

      def to_yaml(doc) = doc.to_yaml

      def to_xml(doc) = doc.to_xml(bibxml: true)

      def to_bibxml(doc) = doc.to_rfcxml
    end
  end
end
