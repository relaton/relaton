# frozen_string_literal: true

require "yeptris/psych"

require "mechanize"
require "loc_mods"
require_relative "../nist"
require_relative "mods_parser"
require_relative "pubs_export"

module Relaton
  module Nist
    class DataFetcher < Core::DataFetcher
      RELEASES_URL = "https://github.com/usnistgov/NIST-Tech-Pubs/releases"
      MODS_ASSET = "allrecords-MODS.xml"

      def fetch(source = nil)
        # An incremental run keeps the tree: unchanged records are not
        # rewritten (Core#force_write) and files this crawl no longer produces
        # are pruned after it completes (Core::DataFetcher.fetch(prune: true)).
        FileUtils.rm Dir[File.join(@output, "*.#{@ext}")] unless prune
        fetch_tech_pubs source
        fetch_csrc
        # add_static_files
        index.save
        report_errors
      end

      def fetch_tech_pubs(source = nil)
        page = Mechanize.new.get(source_url(source))
        # The resolved URI names the concrete release the redirect landed on
        # (latest/download moves as NIST-Tech-Pubs publishes) — log it so every
        # crawl proves which release it read.
        Util.info "NIST-Tech-Pubs release: #{page.uri}", key: "nist"
        docs = LocMods::Collection.from_xml page.body
        docs.mods.each { |doc| write_file ModsParser.new(doc, series, @errors).parse }
      end

      # Supplements the MODS collection with the CSRC pubs-export feed
      # (csrc.nist.gov feeds/metanorma/pubs-export.zip, the same zip
      # PubsExport caches for the runtime): the MODS carries no draft-stage
      # records at all, while the CSRC feed lists them (e.g. FIPS 197 as the
      # 2001 final, upd1, and upd1.ipd). Only draft rows are supplemented —
      # the finals already come from the MODS pass, and a draft row never
      # shadows its base document (relaton#313, the root of relaton#146).
      #
      # A row is built exactly as the runtime builds a CSRC hit
      # (HitCollection#hit_data → Scraper.parse_page), so the crawled record
      # and the live one share one id: the stage, revision and update all come
      # from the row's uri and DOI ("NIST FIPS 197/Upd1 ipd",
      # "NIST SP 800-108r1 ipd", "NIST SP 1800-12 2pd"). A row whose id
      # carries no stage is a final, and is skipped.
      #
      # CSRC lists a republished draft twice, at …/ipd and …/ipd-(1), with one
      # DOI and so one id: the plain uri goes first, and each id is written once.
      def fetch_csrc(rows = PubsExport.instance.data)
        hits = HitCollection.new ""
        codes = Set.new
        plain, republished = rows.partition { |doc| doc["uri"].to_s !~ /-\(\d+\)\z/ }
        (plain + republished).each do |doc|
          bib = csrc_bib hits, doc
          write_file bib if bib && codes.add?(bib.docidentifier.first.content)
        end
      end

      # Builds the record of a draft-stage CSRC row, or nil for a final row or
      # a row that fails to build (recorded in #failures). Write errors are not
      # rescued here: they stop the crawl, as they do in the MODS pass.
      def csrc_bib(hits, doc)
        data = hits.hit_data doc
        return unless pubid(data[:code])&.stage

        bib = Scraper.parse_page data
        # The runtime stamps the fetch date; a crawled record must not, or it
        # changes every day and Core#force_write rewrites it on each crawl.
        bib.fetched = nil
        bib
      rescue StandardError => e
        failures << "CSRC record skipped: #{e.message} (#{doc['docidentifier']}, #{doc['uri']})"
        nil
      end

      # Build the MODS download URL for a NIST-Tech-Pubs release. With no tag
      # (nil, blank, or "latest") use GitHub's `latest/download` redirect so new
      # releases are picked up automatically by the crawler; a concrete tag
      # (e.g. "June2026") pins that specific release.
      def source_url(source = nil)
        tag = source.to_s.strip
        path = tag.empty? || tag.casecmp?("latest") ? "latest/download" : "download/#{tag}"
        "#{RELEASES_URL}/#{path}/#{MODS_ASSET}"
      end

      def write_file(bib)
        id = bib.docidentifier.find(&:primary) || bib.docidentifier.first
        unless id
          failures << "Document skipped: no identifier (#{document_label(bib)})"
          return
        end
        # Distinct docids can sanitize to one filename; take a path of our own
        # rather than overwriting the other document (Core#unique_output_file).
        docid = id.content.sub(/^NIST IR/, "NISTIR")
        file = unique_output_file docid
        if @files.include? file
          # Same reserved path == same docid: a genuine duplicate. Checked FIRST,
          # because a disambiguated path stays != output_file forever.
          Util.warn "File #{file} exists. Docid: #{id.content}"
        elsif file != output_file(docid)
          Util.warn "File #{output_file docid} exists. Docid: #{id.content}. Writing #{file} instead."
        end
        # Serialize before indexing: a record that fails to serialize must not
        # leave an index row that names a file never written.
        content = serialize(bib)
        @files << file
        pid = pubid id.content
        if pid
          index.add_or_update pid, file
        else
          failures << "Unparseable id `#{id.content}` was not indexed (#{file})"
        end
        force_write file, content
      end

      # A human-readable label for a bib with no usable docidentifier, so the
      # skipped record is identifiable in the reported error.
      def document_label(bib)
        Array(bib.title).map(&:content).compact.reject(&:empty?).first || "unknown title"
      end

      # Parse a docidentifier string into a Pubid::Nist::Identifier, or nil if
      # pubid can't parse it — so a single bad id never aborts the crawl or
      # corrupts index-v2. The caller records the failure (see #write_file) so
      # #report_errors can surface it as a tracked GitHub issue.
      def pubid(id)
        ::Pubid::Nist::Identifier.parse id
      rescue StandardError
        nil
      end

      # Per-document failures (unparseable ids, identifier-less records)
      # collected during the crawl and surfaced by #report_errors.
      def failures
        @failures ||= []
      end

      # Surface accumulated per-document failures through the shared error
      # machinery (the "Error fetching documents" GitHub issue in CI) so they
      # are visible and tracked, not a hard crash or a silent stderr warning.
      # The gh_issue channel is registered inside #report_errors, so emit these
      # at :error (via #log_error) after it is set up and before super creates
      # the issue.
      def report_errors
        gh_issue
        failures.each { |msg| log_error msg }
        super
      end

      # def add_static_files
      #   Dir["./static/*.yaml"].each do |file|
      #     bib = Item.from_yaml(File.read(file, encoding: "UTF-8"))
      #     index.add_or_update bib.docidentifier[0].content, file
      #   end
      # end

      def to_yaml(bib)
        Item.to_yaml(bib)
      end

      def to_xml(bib)
        Bibdata.to_xml(bib)
      end

      def to_bibxml(bib)
        bib.to_rfcxml
      end

      def log_error(msg)
        Util.error msg
      end

      def index
        @index ||= Relaton::Index.find_or_create(
          :nist, file: "#{INDEXFILE}.yaml", pubid_class: ::Pubid::Nist::Identifier
        )
      end

      def series
        @series ||= Yeptris::Psych.load_file File.expand_path("series.yaml", __dir__)
      end
    end
  end
end
