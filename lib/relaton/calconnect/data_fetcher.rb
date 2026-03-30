# frozen_string_literal:true

require "yaml"
require "faraday"
require "relaton/core"
require "relaton/index"
require_relative "scraper"
require_relative "util"

module Relaton::Calconnect
  #
  # Relaton-calconnect data fetcher
  #
  class DataFetcher < Relaton::Core::DataFetcher
    # DOMAIN = "https://standards.calconnect.org/"
    # SCHEME, HOST = DOMAIN.split(%r{:?/?/})
    ENDPOINT = "https://standards.calconnect.org/relaton/index.yaml"
    # DATADIR = "data"
    # DATAFILE = File.join DATADIR, "bibliography.yml"
    # ETAGFILE = File.join DATADIR, "etag.txt"

    def etagfile
      @etagfile ||= File.join @output, "etag.txt"
    end

    def index
      @index = Relaton::Index.find_or_create :CC, file: "index-v1.yaml"
    end

    def log_error(msg)
      Util.error msg
    end

    #
    # fetch data form server and save it to file.
    #
    def fetch(_source = nil) # rubocop:disable Metrics/AbcSize
      resp = Faraday.new(ENDPOINT, headers: { "If-None-Match" => etag }).get
      # return if there aren't any changes since last fetching
      return unless resp.status == 200

      data = YAML.safe_load resp.body
      all_success = true
      data["root"]["items"].each { |doc| all_success &&= parse_page doc }
      self.etag = resp[:etag] if all_success
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
      # bib.link.each { |l| l.content.merge!(scheme: SCHEME, host: HOST) unless l.content.host }
      write_doc doc["docid"][0]["id"], bib
      true
    rescue StandardError => e
      Util.warn "Document: #{doc['docid'][0]['id']}"
      Util.warn e.message
      Util.warn e.backtrace[0..5].join("\n")
      false
    end

    def write_doc(docid, bib) # rubocop:disable Metrics/MethodLength
      file = output_file docid
      if @files.include? file
        Util.warn "#{file} exist"
      else
        @files << file
      end
      index.add_or_update docid, file
      File.write file, serialize(bib), encoding: "UTF-8"
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
