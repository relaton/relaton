require "fileutils"
require "moxml"
require "thor"
require "thor/hollaback"
require_relative "cli/util"
require_relative "cli/command"

module Relaton
  def self.db(dir = nil)
    Cli.relaton dir
  end

  module Cli
    class RelatonDb
      include Singleton

      DBCONF = "#{Dir.home}/.relaton/dbpath".freeze

      # @param dir [String, nil]
      # @return [Relaton::Db]
      def db(dir)
        if dir
          FileUtils.mkdir_p File.dirname(DBCONF)
          File.write DBCONF, dir, encoding: "UTF-8"
          @db = Relaton::Db.new dir, nil
        else
          @db ||= Relaton::Db.new dbpath, nil
        end
      end

      private

      # @return [String] path to DB
      def dbpath
        if File.exist?(DBCONF)
          File.read(DBCONF, encoding: "UTF-8")
        else "#{Dir.home}/.relaton/cache"
        end
      end
    end

    class << self
      def version
        # One gem, one version.
        puts "relaton => #{Relaton::VERSION}"
      end

      def start(arguments)
        Relaton::Cli::Command.start(arguments)
      end

      # Relaton
      #
      # Based on current setup, we need to initiate a Db instance to
      # register all of it's supported processor backends. To make it
      # easier we have added it as a class method so we can use this
      # whenever necessary.
      #
      # @param dir [String, nil]
      # @return [Relaton::Db]
      def relaton(dir)
        RelatonDb.instance.db dir
      end

      # Pick the flavor processor from the first docidentifier, in any
      # namespace, and hand it the XML with no namespaces (relaton#581).
      #
      # @param xml [String] a bibdata or bibitem
      # @return [Relaton::Bib::ItemData, nil] nil when the source is not XML
      def parse_xml(xml)
        return unless xml

        doc = Moxml.new.parse(xml)
        plain = without_namespaces(doc)
        if (proc = Cli.processor(doc))
          proc.from_xml(plain)
        else
          Relaton::Bib::Item.from_xml(plain) rescue nil
        end
      rescue Moxml::ParseError
        nil
      end

      # The processor named by the first docidentifier's type, else by the
      # first word of its text.
      #
      # @param doc [Moxml::Document]
      # @return [Relaton::Core::Processor, nil]
      def processor(doc)
        docid = doc.xpath("//*[local-name()='docidentifier']").first
        proc = get_proc docid
        return proc if proc

        Relaton::Db::Registry.instance.by_type(docid&.text&.match(/^\w+/)&.to_s)
      end

      private

      # The root element as XML, with every element and attribute in no
      # namespace (`xml:` attributes keep their prefix). The lutaml-model
      # mappings are namespace-free: they skip a prefixed element, and a
      # nested `relation/bibitem` in a default namespace raises in
      # lutaml-model 0.8.175 (it calls `mappings_for` on `Bib::ItemData`).
      # Moxml cannot drop a namespace in place, so this builds a copy.
      #
      # @param doc [Moxml::Document]
      # @return [String]
      def without_namespaces(doc)
        plain = Moxml.new.create_document
        plain.add_child plain_element(plain, doc.root)
        plain.root.to_xml
      end

      # @param doc [Moxml::Document] the document the copy belongs to
      # @param src [Moxml::Element]
      # @return [Moxml::Element]
      def plain_element(doc, src)
        elm = doc.create_element(src.name)
        # An attribute in no namespace wins over a prefixed one of the
        # same local name (`type` over `a:type`).
        src.attributes.sort_by { |a| a.namespace ? 0 : 1 }.each do |attr|
          elm[plain_name(attr)] = attr.value
        end
        src.children.each { |child| elm.add_child plain_node(doc, child) }
        elm
      end

      # @param attr [Moxml::Attribute]
      # @return [String] the local name; an `xml:` attribute keeps its prefix
      def plain_name(attr)
        attr.namespace&.prefix == "xml" ? "xml:#{attr.name}" : attr.name
      end

      # An entity reference (`&nbsp;`) stays as its text: lutaml-model cannot
      # read an entity it has no declaration for, the way `XmlTree.escape`
      # escapes its `&`. A processing instruction becomes an empty text.
      #
      # @param doc [Moxml::Document]
      # @param src [Moxml::Node]
      # @return [Moxml::Node]
      def plain_node(doc, src)
        case src
        when Moxml::Element then plain_element(doc, src)
        when Moxml::Cdata then doc.create_cdata(src.content)
        when Moxml::Text then doc.create_text(src.content)
        when Moxml::Comment then doc.create_comment(src.content)
        when Moxml::EntityReference then doc.create_text("&#{src.name};")
        else doc.create_text("")
        end
      end

      # @param docid [Moxml::Element, nil]
      # @return [Relaton::Core::Processor, nil]
      def get_proc(docid)
        type = docid&.[]("type")
        return unless type

        Relaton::Db::Registry.instance.by_type(type)
      end
    end
  end
end
