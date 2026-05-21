# frozen_string_literal:true

require "json"
require "mechanize"
require "relaton/core"
require "relaton/index"
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

    def index
      @index = Relaton::Index.find_or_create :CC, file: "index-v1.yaml"
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
      file = output_file slug
      if @files.include? file
        Util.warn "#{file} exist"
      else
        @files << file
      end
      index.add_or_update primary_docid(bib), file
      File.write file, serialize(bib), encoding: "UTF-8"
    end

    # Index entries are keyed by the canonical doc identifier
    # (e.g. "CC/DIR 10005:2019"), not the upstream slug used for filenames.
    def primary_docid(bib)
      docid = bib.docidentifier.find(&:primary) || bib.docidentifier.first
      docid.content
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
