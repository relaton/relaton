require "etc"
require "parallel"
require "pubid"
require "pubid/ietf"
require "relaton/core"
require_relative "../ietf"
require_relative "bibxml_parser"
require_relative "rfc/index"
require_relative "rfc/entry"
require_relative "wg_name_resolver"

module Relaton
  module Ietf
    class DataFetcher < Core::DataFetcher
      #
      # Fetch documents
      #
      def fetch(source)
        @source = source
        case source
        when "ietf-rfcsubseries" then fetch_ieft_rfcsubseries
        when "ietf-internet-drafts" then fetch_ieft_internet_drafts
        when "ietf-rfc-entries" then fetch_ieft_rfcs
        end
        index.save
        report_unindexed
        report_unparsed
      end

      private

      # The published index is the pubid-structured `index-v2` (relaton#109).
      # `pubid_class:` is not decoration: `FileIO#save` serialises an id to its
      # `_type:` hash only when it is an instance of the configured class, so
      # without it — or without parsing the id below — this writes a v1-shaped
      # file under a v2 name.
      # `url: nil` is load-bearing, not decoration. Scraper opens the same
      # `:IETF` pool key with a `url:`, and `Type#actual?` skips the URL check
      # when the caller omits it (`!args.key?(:url)`) — so in a process where a
      # lookup ran first, omitting it here would hand the crawl the
      # remote-backed Type and `save` would write to `~/.relaton/ietf/` instead
      # of `./`, publishing no index at all. Passing it explicitly forces a
      # local-file Type.
      def index
        @index ||= Relaton::Index.find_or_create(
          :IETF, url: nil, file: "#{INDEXFILE}.yaml",
                 pubid_class: ::Pubid::Ietf::Identifier
        )
      end

      #
      # Fetches ietf-rfcsubseries documents
      #
      def fetch_ieft_rfcsubseries
        idx = Rfc::Index.from_xml(rfc_index)
        # Keyed by the normalised doc-id, built once for the whole crawl:
        # `Entry` looks constituents up by `Entry.squish(ref)`, and doing it
        # per-entry over ~9,800 RFCs would rebuild this table 367 times.
        rfc_map = (idx.rfc_entries || []).each_with_object({}) do |entry, h|
          key = Rfc::Entry.squish(entry.doc_id)
          if h.key?(key)
            Util.warn "Duplicate RFC doc-id `#{entry.doc_id}` after normalisation " \
                      "(`#{key}`); the later entry wins for constituent lookup"
          end
          h[key] = entry
        end
        idx.subseries_entries.each do |entry|
          save_doc entry.to_item(rfc_map, wg_names: wg_names)
        end
      end

      #
      # Fetches ietf-internet-drafts documents.
      #
      # Each work unit (one series, or one singleton XML) is processed
      # end-to-end in a worker process: parse → link relations → serialize →
      # write. Workers return Marshal-friendly index entries; the parent
      # collects them and updates `Relaton::Index` and the duplicate-check set
      # serially. Set `RELATON_IETF_PARALLEL_WORKERS=0` to force serial
      # execution (useful for tests and debugging).
      #
      def fetch_ieft_internet_drafts
        series_groups, singleton_paths = group_draft_paths

        series_results = parallelize(series_groups.to_a) do |(series, paths_info)|
          process_series(series, paths_info)
        end.flatten(1)

        singleton_results = parallelize(singleton_paths) do |path|
          process_singleton(path)
        end

        entries, unparsed = (series_results + singleton_results).compact
          .partition { |r| r[:unparsed].nil? }
        # Tallied here, not in the worker: a counter incremented in a Parallel
        # worker process is lost on the way back (see record_index_entry).
        @unparsed = unparsed.map { |r| "#{r[:unparsed]} (#{r[:error]})" }
        entries.each { |r| record_index_entry(r) }
      end

      #
      # Run `block` once per item, in parallel worker processes when configured.
      # `Parallel.map(items, in_processes: 0)` runs synchronously in the
      # current process, which keeps tests deterministic and lets mocks work.
      #
      def parallelize(items, &block)
        Parallel.map(items, in_processes: worker_count, &block)
      end

      def worker_count
        ENV.fetch("RELATON_IETF_PARALLEL_WORKERS", Etc.nprocessors.to_s).to_i
      end

      #
      # Filename-only scan: group versioned drafts by normalized series stem;
      # everything else (non-versioned, non-`D.draft-`) goes to singletons.
      # No XML parsing happens here — workers do that.
      #
      # @return [Array(Hash, Array<String>)]
      #   series_groups: { normalized_series => [{path, ver, ref}, ...] }
      #   singleton_paths: [path, ...]
      #
      def group_draft_paths
        series_groups = {}
        singleton_paths = []
        Dir["bibxml-ids/*.xml"].each do |path|
          file = File.basename(path, ".xml")
          is_draft = file.include?("D.draft-")
          ver = is_draft ? file[/(\d+)$/, 1] : nil
          ref = file.sub(/^reference\.I-D\./, "").downcase
          stem_match = is_draft && ver ? /^(draft-.+)-(\d{2})$/.match(ref) : nil
          if stem_match
            series = stem_match[1].gsub(/[.\s\/:-]+/, "-")
            (series_groups[series] ||= []) << { path: path, ver: ver, ref: ref }
          else
            singleton_paths << path
          end
        end
        [series_groups, singleton_paths]
      end

      #
      # Worker: parse all files in a series, sort by version, append
      # immediate-neighbor relations (skipped for bibxml), write each version
      # and the un-versioned aggregator doc. Returns an array of index entries
      # for the parent.
      #
      def process_series(series, paths_info)
        parsed = paths_info.sort_by { |p| p[:ver].to_i }.map do |p|
          bib, marker = parse_bibxml(p[:path])
          next marker unless bib

          bib.version = [Bib::Version.new(draft: p[:ver])]
          p.merge(bib: bib, source: bib.source)
        end
        # A file that failed to parse must not reach `sorted`:
        # link_neighbor_relations and build_unversioned_doc both dereference
        # `entry[:bib]`, and a dropped version is better than a nil one.
        sorted, skipped = parsed.partition { |e| e[:unparsed].nil? }
        link_neighbor_relations(sorted) if @format != "bibxml"

        results = sorted.map { |entry| serialize_and_write(entry[:bib]) }
        results << serialize_and_write(build_unversioned_doc(series, sorted)) if @format != "bibxml"
        results.compact + skipped
      end

      #
      # Worker: parse + serialize + write a single non-grouped XML.
      #
      def process_singleton(path)
        file = File.basename(path, ".xml")
        is_draft = file.include?("D.draft-")
        ver = is_draft ? file[/(\d+)$/, 1] : nil
        bib, marker = parse_bibxml(path)
        return marker unless bib

        bib.version = [Bib::Version.new(draft: ver)] if ver
        serialize_and_write(bib)
      end

      #
      # Read and parse one bibxml file, or nil if it cannot be parsed.
      #
      # Rescues `StandardError` rather than a narrow list on purpose: lutaml
      # raises `InvalidFormatError` on bad bytes, but the converter also runs
      # regexes over parsed text (`parse_surname_initials` and friends), and
      # those raise `ArgumentError: invalid byte sequence` on anything that slips
      # through. One unparseable file must cost one document, never the crawl —
      # the drafts path runs under Parallel.map, which discards every result from
      # the pass when a worker raises.
      #
      # @param path [String]
      # @return [Relaton::Ietf::ItemData, nil]
      #
      # @param path [String]
      # @return [Array(Relaton::Ietf::ItemData, nil), Array(nil, Hash)]
      #   the record, or nil plus a marker carrying why
      def parse_bibxml(path)
        bib = BibXMLParser.parse(read_bibxml(path))
        bib ? [bib, nil] : [nil, unparsed_marker(path, "parser returned no record")]
      rescue StandardError => e
        [nil, unparsed_marker(path, "#{e.class}: #{e.message.to_s.lines.first.to_s.strip}")]
      end

      # Marshal-friendly stand-in for a record, carried back to the parent so the
      # skip can be counted where a tally survives. The reason rides along rather
      # than sitting in an ivar, which a later file would overwrite.
      def unparsed_marker(path, error)
        { unparsed: path, error: error }
      end

      #
      # Read a bibxml file as UTF-8, recovering Windows-1252 bytes.
      #
      # These files declare `encoding='UTF-8'` but some carry CP1252 — smart
      # quotes and accented Latin letters. `File.read(encoding: "UTF-8")` only
      # *tags* the string, so those reach lutaml as invalid UTF-8 and it raises.
      #
      # `scrub` with a block transcodes each invalid *run* as CP1252 while
      # leaving valid UTF-8 untouched. Both halves matter:
      #
      # * Not plain `scrub`, which substitutes U+FFFD: `client’s` would become
      #   `client\uFFFDs` and `Muñoz` `Mu\uFFFDoz` — author surnames included.
      #   The damage is length-preserving, so a length check will not catch it.
      # * Not a whole-file CP1252 re-decode, which mangles a file that is
      #   genuinely UTF-8 apart from one stray byte: `Muñoz café ’` would come
      #   back as `MuÃ±oz cafÃ© ’`, silently, since the result is valid UTF-8 and
      #   nothing raises. No such file exists in today's corpus (0 of the 125
      #   affected contain valid multi-byte UTF-8) but it grows daily, and
      #   "decodes losslessly as CP1252" is weak evidence of correctness —
      #   CP1252 maps 251 of 256 byte values.
      #
      # `undef: :replace` covers the five bytes CP1252 leaves undefined
      # (0x81 0x8D 0x8F 0x90 0x9D), so this returns valid UTF-8 rather than
      # raising and costing the whole file.
      #
      # @param path [String]
      # @return [String] UTF-8, valid encoding
      #
      def read_bibxml(path)
        utf8 = File.binread(path).force_encoding(Encoding::UTF_8)
        return utf8 if utf8.valid_encoding?

        utf8.scrub do |bad|
          bad.force_encoding(Encoding::WINDOWS_1252)
             .encode(Encoding::UTF_8, undef: :replace)
        end
      end

      #
      # Append immediate-neighbor `updates` / `updatedBy` relations in memory.
      # Single-version series get no relations (no neighbors).
      #
      def link_neighbor_relations(sorted)
        sorted.each_with_index do |entry, i|
          if i.positive?
            prev = sorted[i - 1]
            entry[:bib].relation << version_relation({ ref: prev[:ref], source: prev[:source] }, "updates")
          end
          if i < sorted.size - 1
            nxt = sorted[i + 1]
            entry[:bib].relation << version_relation({ ref: nxt[:ref], source: nxt[:source] }, "updatedBy")
          end
        end
      end

      #
      # Build (but do not write) the un-versioned series aggregator doc with
      # `includes` relations to every version. Uses the latest version's
      # title/abstract from memory.
      #
      # The aggregator is *synthesised* — there is no upstream document for it,
      # so `date`, `ext` (hence doctype) and `source` can only be inherited from
      # its newest constituent, which `sorted` already holds in memory. Without
      # that inheritance it publishes undated (and so unsorted on the Pages
      # index, which sorts by date) and with no document type at all.
      #
      # @return [Relaton::Ietf::ItemData, nil]
      #
      def build_unversioned_doc(series, sorted)
        if sorted.empty?
          Util.warn "No versions found for #{series}"
          return nil
        end

        last_v = sorted.last[:bib]
        docid = Bib::Docidentifier.new(type: "Internet-Draft", content: series, primary: true)
        rel = sorted.map { |e| version_relation({ ref: e[:ref], source: e[:source] }, "includes") }
        ItemData.new(
          title: last_v.title, abstract: last_v.abstract, formattedref: Bib::Formattedref.new(content: series),
          docidentifier: [docid], relation: rel,
          # dup'd, not shared: these are the newest version's own objects, and
          # aliasing them would make any later edit to the aggregator mutate the
          # `-NN` record too.
          date: last_v.date&.dup, ext: last_v.ext&.dup, source: last_v.source&.dup
        )
      end

      #
      # Create bibitem relation
      #
      # @param [Hash] ver version reference, { ref:, source: }
      # @param [String] type relation type
      #
      # @return [Relaton::Ietf::Relation] relation
      #
      def version_relation(ver, type)
        docid = Bib::Docidentifier.new(type: "Internet-Draft", content: ver[:ref], primary: true)
        bibitem = ItemData.new(formattedref: Bib::Formattedref.new(content: ver[:ref]), docidentifier: [docid], source: ver[:source])
        Relaton::Ietf::Relation.new(type: type, bibitem: bibitem)
      end

      #
      # Fetches ietf-rfc-entries documents
      #
      def fetch_ieft_rfcs
        idx = Rfc::Index.from_xml(rfc_index)
        idx.rfc_entries.each do |entry|
          save_doc entry.to_item(nil, wg_names: wg_names)
        rescue StandardError => e
          Util.error "Error parsing #{entry.doc_id}: #{e.message}\n" \
            "#{e.backtrace[0..5].join("\n")}"
        end
      end

      #
      # Get RFC index
      #
      # @return [Nokogiri::XML::Document] RFC index
      #
      def rfc_index
        uri = URI "https://www.rfc-editor.org/rfc-index.xml"
        Net::HTTP.get(uri)
      end

      def wg_names
        @wg_names ||= WgNameResolver.fetch
      end

      #
      # Save document to file (sequential path: serialize, write, index).
      # Used by the rfcsubseries / rfc-entries fetchers; the I-D fetcher splits
      # this into worker-safe `serialize_and_write` plus parent-only
      # `record_index_entry` so the index is touched only in the main process.
      #
      # @param [Relaton::Ietf::Rfc::Entry, nil] entry
      # @param [Boolean] check_duplicate check for duplicate
      #
      def save_doc(entry, check_duplicate: true)
        result = serialize_and_write(entry)
        record_index_entry(result, check_duplicate: check_duplicate) if result
      end

      #
      # Worker-safe: serialize, compute output filename, write to disk, return
      # a Marshal-friendly hash with the docid+file pair the parent needs to
      # update `Relaton::Index` and `@files`. Does NOT touch instance state
      # that has to stay consistent across workers (`@files`, the index).
      #
      # @param [#to_yaml, #to_xml, #to_rfcxml, nil] entry
      # @return [Hash, nil]
      #
      def serialize_and_write(entry) # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity
        return nil unless entry

        content = case @format
                  when "xml" then entry.to_xml(bibdata: true)
                  when "yaml" then entry.to_yaml
                  when "bibxml" then entry.to_rfcxml
                  else entry.send("to_#{@format}")
                  end
        id = if entry.respond_to?(:docidentifier)
               entry.docidentifier.detect { |i| i.type == "Internet-Draft" && i.primary }&.content
             end
        id ||= entry.docnumber || entry.formattedref.content
        file = output_file(id)
        File.write file, content, encoding: "UTF-8"
        primary = entry.docidentifier.detect(&:primary) || entry.docidentifier.first
        { docnumber: entry.docnumber, file: file, index_id: primary.content,
          pubid: parse_pubid(primary.content) }
      end

      #
      # Parse a record's primary docidentifier into the pubid the index stores.
      #
      # Deliberately here rather than in `record_index_entry`: this runs inside
      # the `Parallel` workers, and a pubid identifier survives the Marshal round
      # trip Parallel does on the return value. Parsing in the parent instead
      # would put ~0.7 ms per record back on the serial path — some minutes over
      # the 167k-draft crawl, all of it outside the parallelism this fetcher is
      # built around.
      #
      # @param [String] content primary docidentifier content
      # @return [Pubid::Ietf::Identifier, nil] nil when pubid rejects it
      #
      def parse_pubid(content)
        ::Pubid::Ietf::Identifier.parse content
      rescue StandardError => e
        # Full message: the tail is the part that says *what shape* pubid
        # stopped accepting, which is the whole point of the warning.
        Util.warn "Not indexing `#{content}`: #{e.message}"
        nil
      end

      #
      # Parent-only: dedupe-check `@files` and update `Relaton::Index`. Called
      # serially after workers return so index updates are race-free.
      #
      def record_index_entry(result, check_duplicate: true)
        if check_duplicate && @files.include?(result[:file])
          Util.warn "File #{result[:file]} already exists. Document: #{result[:docnumber]}"
        elsif check_duplicate
          @files << result[:file]
        end
        # A record whose identifier pubid rejects is written but not indexed —
        # never fatal. The index load is all-or-nothing (`deserialize_id` raises
        # on the first bad id and `load_index` then rejects the *entire* index),
        # so one malformed upstream record must cost one document, not every
        # lookup. All 176,862 published ids parse today; this guards drift.
        # Counted here, in the parent, because a worker's tally would be lost.
        unless result[:pubid]
          @unindexed = @unindexed.to_i + 1
          return
        end

        index.add_or_update result[:pubid], result[:file]
      end

      # Skips are per-record warnings in a crawl that writes ~177k of them, so
      # restate the total where it can actually be noticed.
      # One line for a crawl that reads ~167k files, not one per skip.
      def report_unparsed
        return if @unparsed.nil? || @unparsed.empty?

        Util.warn "#{@unparsed.size} file(s) skipped: could not be parsed. " \
                  "First: #{@unparsed.first(5).join(', ')}"
      end

      def report_unindexed
        return unless @unindexed.to_i.positive?

        Util.warn "#{@unindexed} document(s) written but not indexed: " \
                  "identifier not parseable by Pubid::Ietf"
      end

    end
  end
end
