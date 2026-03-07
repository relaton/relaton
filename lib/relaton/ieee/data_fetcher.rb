require "zip"
require_relative "../ieee"
require_relative "converter/bibxml"
require_relative "idams_parser"
require_relative "rawbib_id_parser"

module Relaton
  module Ieee
    class DataFetcher < Core::DataFetcher
      RELATION_TYPES = {
        "S" => { type: "obsoletedBy" },
        "V" => { type: "updates", description: "revises" },
        "T" => { type: "updates", description: "amends" },
        "C" => { type: "updates", description: "corrects" },
        "O" => { type: "adoptedFrom" },
        "P" => { type: "complementOf", description: "supplement" },
        "N" => false, "G" => false,
        "F" => false, "I" => false,
        "E" => false, "B" => false, "W" => false
      }.freeze

      #
      # Convert documents from `ieee-rawbib` dir (IEEE dataset) to BibYAML/BibXML
      #
      def fetch(_source = nil) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        Dir["ieee-rawbib/**/*.{xml,zip}"].reject { |f| f["Deleted_"] }.each do |f|
          xml = case File.extname(f)
                when ".zip" then read_zip f
                when ".xml" then File.read f, encoding: "UTF-8"
                end
          fetch_doc xml, f
        rescue StandardError => e
          Util.error "File: #{f}\n#{e.message}\n#{e.backtrace}"
        end
        # File.write "normtitles.txt", @normtitles.join("\n")
        update_relations
      end

      # @return [Hash] list of AMSID => PubID
      def backrefs
        @backrefs ||= {}
      end

      #
      # Save unresolved relation reference
      #
      # @param [String] docnumber of main document
      # @param [Nokogiri::XML::Element] amsid relation data
      #
      def add_crossref(docnumber, amsid)
        return if RELATION_TYPES[amsid.type] == false

        ref = { amsid: amsid.date_string, type: amsid.type }
        crossrefs[docnumber] << ref
      end

      #
      # Create relation instance
      #
      # @param [String] type IEEE relation type
      # @param [String] fref reference
      #
      # @return [RelatonBib::DocumentRelation]
      #
      def create_relation(type, fref)
        unless RELATION_TYPES.key? type
          Util.warn "Unknown relation type: '#{type}' for reference '#{fref}'", key: fref
          return
        end
        return if RELATION_TYPES[type] == false

        docid = Bib::Docidentifier.new(type: "IEEE", content: fref, primary: true)
        bib = ItemData.new formattedref: fref, docidentifier: [docid]
        description = create_relation_description type
        Bib::Relation.new(type: RELATION_TYPES[type][:type], description: description, bibitem: bib)
      end

      private

      def create_relation_description(type)
        desc = RELATION_TYPES[type][:description] if RELATION_TYPES[type]
        return unless desc

        desc && Bib::LocalizedMarkedUpString.new(content: desc, language: "en", script: "Latn")
      end

      # @return [Hash] list of PubID => list of unresolved relations
      def crossrefs
        @crossrefs ||= Hash.new { |hash, key| hash[key] = [] }
      end

      #
      # Extract XML file from zip archive
      #
      # @param [String] file path to achive
      #
      # @return [String] file content
      #
      def read_zip(file)
        Zip::File.open(file) do |zf|
          entry = zf.glob("**/*.xml").first
          entry.get_input_stream.read
        end
      end

      #
      # Parse document and save it
      #
      # @param [String] xml content
      # @param [String] filename source file
      #
      def fetch_doc(xml, filename) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        begin
          doc = ::Ieee::Idams::Publication.from_xml(xml)
        rescue StandardError
          Util.warn "Empty file: `#{filename}`"
          return
        end
        return if doc.publicationinfo&.standard_id == "0"

        bib = IdamsParser.new(doc, self).parse
        if bib.docnumber.nil?
          Util.warn "PubID parse error. Normtitle: `#{doc.normtitle}`, file: `#{filename}`"
          return
        end
        amsid = doc.publicationinfo.amsid
        if backrefs.value?(bib.docidentifier[0].content) && /updates\.\d+/ !~ filename
          oamsid = backrefs.key bib.docidentifier[0].content
          Util.warn "Document exists ID: `#{bib.docidentifier[0].content}` AMSID: " \
              "`#{amsid}` source: `#{filename}`. Other AMSID: `#{oamsid}`"
          if bib.docidentifier.find(&:primary).content.include?(doc.publicationinfo.stdnumber)
            save_doc bib # rewrite file if the PubID matches to the stdnumber
            backrefs[amsid] = bib.docidentifier[0].content
          end
        else
          save_doc bib
          backrefs[amsid] = bib.docidentifier[0].content
        end
      end

      #
      # Save document to file
      #
      # @param [RelatonIeee::IeeeBibliographicItem] bib
      #
      def save_doc(bib)
        File.write output_file(bib.docnumber), serialize(bib), encoding: "UTF-8"
      end

      def to_yaml(bib) = bib.to_yaml
      def to_xml(bib) = bib.to_xml(bibdata: true)
      def to_bibxml(bib) = bib.to_rfcxml

      #
      # Update unresoverd relations
      #
      def update_relations # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        crossrefs.each do |dnum, rfs|
          bib = nil
          rfs.each do |rf|
            if backrefs[rf[:amsid]]
              rel = create_relation(rf[:type], backrefs[rf[:amsid]])
              if rel
                bib ||= read_bib(dnum)
                bib.relation << rel
                save_doc bib
              end
            else
              Util.warn "Unresolved relation: '#{rf[:amsid]}' type: '#{rf[:type]}' for '#{dnum}'"
            end
          end
        end
      end

      #
      # Read document form BibXML/BibYAML file
      #
      # @param [String] docnumber
      #
      # @return [RelatonIeee::IeeeBibliographicItem]
      #
      def read_bib(docnumber)
        c = File.read output_file(docnumber), encoding: "UTF-8"
        case @format
        when "xml" then Item.from_xml c
        when "bibxml" then Converter::BibXml.to_item c
        else Item.from_yaml c
        end
      end
    end
  end
end
