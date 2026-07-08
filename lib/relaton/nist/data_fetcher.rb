# frozen_string_literal: true

require "yaml"
require "mechanize"
require "loc_mods"
require_relative "../nist"
require_relative "mods_parser"

module Relaton
  module Nist
    class DataFetcher < Core::DataFetcher
      RELEASES_URL = "https://github.com/usnistgov/NIST-Tech-Pubs/releases"
      MODS_ASSET = "allrecords-MODS.xml"

      def fetch(source = nil)
        FileUtils.rm Dir[File.join(@output, "*.#{@ext}")]
        fetch_tech_pubs source
        # add_static_files
        index.save
        report_errors
      end

      def fetch_tech_pubs(source = nil)
        xml_data = Mechanize.new.get(source_url(source)).body
        docs = LocMods::Collection.from_xml xml_data
        docs.mods.each { |doc| write_file ModsParser.new(doc, series, @errors).parse }
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
        file = output_file id.content.sub(/^NIST IR/, "NISTIR")
        if @files.include? file
          Util.warn "File #{file} exists. Docid: #{id.content}"
        else @files << file
        end
        pid = pubid id.content
        index.add_or_update pid, file if pid
        File.write file, serialize(bib), encoding: "UTF-8"
      end

      # Parse a docidentifier string into a Pubid::Nist::Identifier; nil (with a
      # warning) if pubid can't parse it, so a single bad id never aborts the
      # crawl or corrupts index-v2.
      def pubid(id)
        ::Pubid::Nist::Identifier.parse id
      rescue StandardError => e
        Util.warn "Failed to parse `#{id}` with pubid: #{e.message}"
        nil
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
