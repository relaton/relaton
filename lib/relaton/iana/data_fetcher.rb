require "relaton/core"
require_relative "../iana"
require_relative "parser"

module Relaton
  module Iana
    class DataFetcher < Core::DataFetcher
      #
      # Parse documents
      #
      def fetch(_source = nil)
        Dir["iana-registries/**/*.xml"].each do |file|
          content = File.read file, encoding: "UTF-8"
          parse(content) if content.include? "<registry"
        rescue StandardError => e
          Util.error "Error: #{e.message}. File: #{file}"
        end
        index.save
      end

      private

      def index
        @index ||= Relaton::Index.find_or_create :iana, file: "#{INDEX_FILE}.yaml"
      end

      def parse(content)
        xml = Nokogiri::XML(content)
        registry = xml.at("/xmlns:registry")
        doc = Parser.parse registry
        save_doc doc
        registry.xpath("./xmlns:registry").each { |r| save_doc Parser.parse(r, doc) }
      end

      #
      # Save document to file
      #
      # @param [RelatonIana::IanaBibliographicItem, nil] bib bibliographic item
      #
      def save_doc(bib) # rubocop:disable Metrics/MethodLength
        return unless bib

        file = output_file(bib.docnumber)
        if @files.include? file
          Util.warn "File #{file} already exists. Document: #{bib.docnumber}"
        else
          @files << file
        end
        index.add_or_update bib.docnumber, file
        File.write file, serialize(bib), encoding: "UTF-8"
      end

      def to_xml(bib)
        bib.to_xml(bibdata: true)
      end

      def to_yaml(bib)
        bib.to_yaml
      end
    end
  end
end
