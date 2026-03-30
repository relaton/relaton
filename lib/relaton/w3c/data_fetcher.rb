require "relaton/core"
require "w3c_api"
require_relative "../w3c"
require_relative "rate_limit_handler"
require_relative "data_parser"
require_relative "pubid"

module Relaton
  module W3c
    class DataFetcher < Core::DataFetcher
      include Relaton::W3c::RateLimitHandler

      def index
        @index ||= Relaton::Index.find_or_create(:W3C, file: "#{INDEXFILE}.yaml")
      end

      def log_error(msg)
        Util.error msg
      end

      def client
        @client ||= W3cApi::Client.new
      end

      #
      # Parse documents
      #
      def fetch(_source = nil)
        specs = client.specifications
        loop do
          specs.links.specifications.each do |spec|
            fetch_spec spec
          end

          break unless specs.next?

          specs = specs.next
        end
        index.save
        report_errors
      end

      def fetch_spec(unrealized_spec)
        spec = realize unrealized_spec
        save_doc DataParser.parse(spec, @errors)

        if spec.links.respond_to?(:version_history) && spec.links.version_history
          version_history = realize spec.links.version_history
          version_history.links.spec_versions.each { |version| save_doc DataParser.parse(realize version) }
        end

        if spec.links.respond_to?(:predecessor_versions) && spec.links.predecessor_versions
          predecessor_versions = realize spec.links.predecessor_versions
          predecessor_versions.links.predecessor_versions.each { |version| save_doc DataParser.parse(realize version) }
        end

        if spec.links.respond_to?(:successor_versions) && spec.links.successor_versions
          successor_versions = realize spec.links.successor_versions
          successor_versions.links.successor_versions.each { |version| save_doc DataParser.parse(realize version) }
        end
      end

      #
      # Save document to file
      #
      # @param [Relaton::W3c::ItemData, nil] bib bibliographic item
      #
      def save_doc(bib, warn_duplicate: true)
        return unless bib

        file = file_name(bib.docnumber)
        if @files.include?(file)
          Util.warn "File #{file} already exists. Document: #{bib.docnumber}" if warn_duplicate
        else
          pubid = PubId.parse bib.docnumber
          index.add_or_update pubid.to_hash, file
          @files << file
        end
        File.write file, serialize(bib), encoding: "UTF-8"
      end

      def to_xml(bib)
        bib.to_xml(bibdata: true)
      end

      def to_yaml(bib)
        bib.to_yaml
      end

      def to_bibxml(bib)
        bib.to_xml
      end

      #
      # Generate file name
      #
      # @param [String] id document id
      #
      # @return [String] file name
      #
      def file_name(id)
        name = id.sub(/^W3C\s/, "").gsub(/[\s,:\/+]/, "_").squeeze("_").downcase
        File.join @output, "#{name}.#{@ext}"
      end
    end
  end
end
