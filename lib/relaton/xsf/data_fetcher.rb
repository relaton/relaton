require "relaton/core"

module Relaton
  module Xsf
    class DataFetcher < Relaton::Core::DataFetcher
      def index
        @index ||= Relaton::Index.find_or_create :xsf, file: "#{INDEXFILE}.yaml"
      end

      def fetch(_source = nil)
        agent = Mechanize.new
        resp = agent.get "https://xmpp.org/extensions/refs/"
        resp.xpath("//a[contains(@href, 'XEP-')]").each do |link|
          doc = agent.get link[:href]
          bib = Relaton::Bib::Converter::BibXml.to_item doc.body
          save_doc bib
        rescue StandardError => e
          Util.warn "Failed to parse #{link[:href]}: #{e.message}"
        end
        index.save
      end

      def save_doc(bib)
        return unless bib

        bib.ext ||= Relaton::Bib::Ext.new
        bib.ext.flavor = "xsf"

        docid = bib.docidentifier.detect(&:primary) || bib.docidentifier.first
        id = docid&.content
        return unless id

        file = output_file id
        if @files.include? file
          Util.warn "File #{file} already exists"
        else
          @files << file
        end
        File.write file, serialize(bib), encoding: "UTF-8"
        index.add_or_update id, file
      end

      def to_yaml(bib)
        bib.to_yaml
      end

      def to_xml(bib)
        bib.to_xml bibdata: true
      end

      def to_bibxml(bib)
        bib.to_rfcxml
      end
    end
  end
end
