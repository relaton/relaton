require_relative "cover"
require_relative "stagename"

module Relaton
  module Plateau
    class BibItem < RelatonBib::BibliographicItem
      # @return [Relaton::Plateau::Cover, nil]
      attr_reader :cover

      # @return [Relaton::Plateau::Stagename, nil]
      attr_reader :stagename

      # @return [Integer, nil]
      attr_accessor :filesize

      def initialize(**args)
        @cover = args.delete(:cover)
        @filesize = args.delete(:filesize)
        @stagename = args.delete(:stagename)
        super(**args)
      end

      #
      # Fetch flavor schema version
      #
      # @return [String] schema version
      #
      def ext_schema
        @ext_schema ||= schema_versions["relaton-model-plateau"]
      end

      # @param opts [Hash]
      # @option opts [Nokogiri::XML::Builder] :builder XML builder
      # @option opts [Boolean] bibdata
      # @option opts [Symbol, nil] :date_format (:short), :full
      # @option opts [String] :lang language
      def to_xml(**opts)
        super do |builder|
          if opts[:bibdata] && has_ext?
            ext = builder.ext do |b|
              doctype&.to_xml b
              b.subdoctype subdoctype if subdoctype
              editorialgroup&.to_xml b
              ics.each { |i| b.ics i }
              structuredidentifier&.to_xml b
              stagename&.to_xml b
              cover&.to_xml b
              b.filesize filesize if filesize
            end
            ext["schema-version"] = ext_schema if !opts[:embedded] && respond_to?(:ext_schema) && ext_schema
          end
        end
      end

      def to_hash
        hash = super
        return hash unless has_ext?

        hash["ext"] ||= {}
        hash["ext"]["stagename"] = stagename.to_hash if stagename
        hash["ext"]["cover"] = cover.to_hash if cover
        hash["ext"]["filesize"] = filesize if filesize
        hash
      end

      def to_asciibib(prefix = "")
        pref = prefix.empty? ? "" : "#{prefix}."
        output = super
        output += stagename.to_asciibib prefix if stagename
        output += cover.to_asciibib prefix if cover
        output += "#{pref}filesize:: #{filesize}\n" if filesize
        output
      end

      def to_all_editions(hits)
        return self if hits.size < 2

        me = deep_clone
        me.docidentifier.each(&:remove_edition)
        me.id.sub!(/#{Regexp.escape(me.edition.content)}$/, "")
        me.instance_variable_set :@edition, nil
        me.date = []
        me.instance_variable_set :@link, []
        me.filesize = nil
        hits.each do |h|
          me.relation << RelatonBib::DocumentRelation.new(type: "hasEdition", bibitem: h.bibitem)
        end
        me
      end

      private

      def has_ext?
        super || stagename || cover || filesize
      end
    end
  end
end
