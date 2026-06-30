# frozen_string_literal: true

require "fileutils"
require "faraday"
require "json"
require_relative "../ogc"
require_relative "scraper"

module Relaton
  module Ogc
    class DataFetcher < Core::DataFetcher
      ENDPOINT = "https://raw.githubusercontent.com/opengeospatial/NamingAuthority/master/definitions/docs/docs.json"

      def initialize(output, format)
        super
        @etagfile = File.join output, "etag.txt"
        @docids = []
        @dupids = Set.new
      end

      def log_error(msg)
        Util.error msg
      end

      def index
        @index ||= Relaton::Index.find_or_create :ogc, file: "#{INDEXFILE}.yaml"
      end

      def fetch(_source = nil) # rubocop:disable Metrics/AbcSize
        get_data do |etag, json|
          no_errors = true
          json.each_value { |hit| fetch_doc(hit) || no_errors = false }
          if @dupids.any?
            Util.warn "Duplicated documents: #{@dupids.to_a.join(', ')}"
          end
          self.etag = etag if no_errors
          index.save
          report_errors
        end
      end

      def fetch_doc(hit)
        return if hit["type"] == "CC"

        bib = Scraper.parse_page hit, @errors
        write_document bib
        true
      rescue StandardError => e
        Util.error "Fetching document: #{hit['identifier']}\n" \
                   "#{e.class} #{e.message}\n#{e.backtrace}"
        false
      end

      def write_document(bib) # rubocop:disable Metrics/AbcSize
        docid = bib.docidentifier[0].content
        if @docids.include?(docid)
          @dupids << docid
          return
        end

        @docids << docid
        file = file_name bib
        index.add_or_update docid, file
        File.write file, serialize(bib), encoding: "UTF-8"
      end

      def file_name(bib)
        name = bib.docidentifier[0].content.upcase.gsub(/[\s:.]/, "_")
        "#{@output}/#{name}.#{@ext}"
      end

      def to_yaml(bib)
        Item.to_yaml bib
      end

      def to_xml(bib)
        Bibdata.to_xml bib
      end

      def to_bibxml(_bib)
        raise NotImplementedError, "OGC does not support bibxml format"
      end

      # @return [String, nil]
      def etag
        @etag ||= if File.exist? @etagfile
                    File.read @etagfile, encoding: "UTF-8"
                  end
      end

      # @param e_tag [String]
      def etag=(e_tag)
        File.write @etagfile, e_tag, encoding: "UTF-8"
      end

      def get_data # rubocop:disable Metrics/AbcSize
        h = {}
        h["If-None-Match"] = etag if etag
        resp = Faraday.new(ENDPOINT, headers: h).get
        case resp.status
        when 200
          json = JSON.parse(resp.body)
          block_given? ? yield(resp[:etag], json) : json
        when 304 then []
        else raise Relaton::RequestError, "Could not access #{ENDPOINT}"
        end
      end
    end
  end
end
