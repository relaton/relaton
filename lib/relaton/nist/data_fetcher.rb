# frozen_string_literal: true

require "yaml"
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
        FileUtils.rm Dir[File.join(@output, "*.#{@ext}")]
        fetch_tech_pubs source
        fetch_csrc
        # add_static_files
        index.save
        report_errors
      end

      def fetch_tech_pubs(source = nil)
        xml_data = Mechanize.new.get(source_url(source)).body
        docs = LocMods::Collection.from_xml xml_data
        docs.mods.each { |doc| write_file ModsParser.new(doc, series, @errors).parse }
      end

      # Supplements the MODS collection with the CSRC pubs-export feed
      # (csrc.nist.gov feeds/metanorma/pubs-export.zip, the same zip
      # PubsExport caches for the runtime): the MODS carries no draft-stage
      # records at all, while the CSRC feed lists them (e.g. FIPS 197 as the
      # 2001 final, upd1, and upd1.ipd). Only draft rows are supplemented —
      # the finals already come from the MODS pass, and a draft row never
      # shadows its base document (relaton#313, the root of relaton#146).
      def fetch_csrc(rows = PubsExport.instance.data)
        rows.each do |doc|
          stage = doc["uri"].to_s[%r{/([a-z]+)\)?\z}, 1]
          next unless stage && stage != "final"

          bib = csrc_bib doc, stage
          write_file bib if bib
        end
      end

      # Builds the draft-stage record from a CSRC feed row. The stage comes
      # from the uri tail (/pubs/fips/197/ipd → "ipd"): the row's
      # docidentifier alone ("FIPS 197") is shared by every stage of the
      # document, and pubid resolves the stage-suffixed form
      # ("NIST FIPS 197 ipd") into a stage-carrying identifier.
      def csrc_bib(doc, stage)
        abbr = doc["series"].to_s.sub(/\Anist-/, "").upcase
        id_content = "NIST #{abbr} #{doc['docnumber']} #{stage}".squeeze(" ")
        args = {
          title: [Bib::Title.new(content: doc["title-main"], type: "title-main",
                                 language: "en", script: "Latn")],
          docidentifier: [Docidentifier.new(content: id_content, type: "NIST",
                                            primary: true)],
          source: [Bib::Uri.new(content: doc["uri"].to_s, type: "src")],
          ext: Ext.new(doctype: Doctype.new(content: "standard"), flavor: "nist"),
        }
        if (issued = doc["issued-date"])
          args[:date] = [Date.new(type: "issued", at: issued)]
        end
        ItemData.new(**args)
      rescue StandardError => e
        failures << "CSRC record skipped: #{e.message} (#{doc['docidentifier']})"
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
        @files << file
        pid = pubid id.content
        if pid
          index.add_or_update pid, file
        else
          failures << "Unparseable id `#{id.content}` was not indexed (#{file})"
        end
        File.write file, serialize(bib), encoding: "UTF-8"
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
        @series ||= YAML.load_file File.expand_path("series.yaml", __dir__)
      end
    end
  end
end
