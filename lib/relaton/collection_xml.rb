require "lutaml/model"
require "lutaml/xml"
require "moxml"

module Relaton
  # The namespace of a `relaton-collection` document.
  class CollectionNamespace < Lutaml::Xml::W3c::XmlNamespace
    uri "https://open.ribose.com/relaton-xml"
    element_form_default :qualified
  end

  # The lutaml-model XML mapping of `Relaton::Bibcollection` (relaton#459).
  #
  # A collection is read in any namespace (a collection an older relaton
  # wrote, or one with no namespace at all), and written in
  # `CollectionNamespace`.
  #
  # The title and the author keep their inline markup (`<em>`, …) as a
  # String, as the model always held them. An item element carries no type
  # discriminator, and its class is a flavor's (chosen by its
  # docidentifier), so `relation` is mapped with custom methods: each item
  # is read by `Bibdata.from_xml` or `Bibcollection.from_xml`, and written
  # by its own `to_xml`.
  #
  # The markup and each item's XML go into the tree as an `XmlRawFragment`,
  # exactly as written: a copy element by element into lutaml's data model
  # loses foreign namespaces (MathML, `xlink:`, `xml:lang`), named entities
  # and comments, and the pretty-printer adds whitespace to mixed content.
  class CollectionXml < Lutaml::Model::Serializable
    model Bibcollection

    attribute :title, :string, collection: true
    attribute :author, :string, collection: true
    attribute :doctype, :string

    xml do
      root "relaton-collection"
      namespace CollectionNamespace

      map_attribute "type", to: :doctype
      map_element "title", to: :title,
                           with: { from: :title_from_xml, to: :title_to_xml }
      map_element "contributor", to: :author,
                                 with: { from: :author_from_xml, to: :author_to_xml }
      map_element "relation", to: :items,
                              with: { from: :items_from_xml, to: :items_to_xml }
    end

    def title_from_xml(model, value)
      model.title = XmlTree.inner_xml first(value)
    end

    def title_to_xml(model, parent, _doc)
      parent.add_child XmlTree.element("title", model.title) if model.title
    end

    def author_from_xml(model, value)
      contributor = Array(value).find do |c|
        child(c, "role")&.attributes&.values&.any? do |a|
          a.name == "type" && a.value == "author"
        end
      end
      model.author = XmlTree.inner_xml child(child(contributor, "organization"), "name")
    end

    def author_to_xml(model, parent, _doc)
      return unless model.author

      role = XmlTree.element("role")
      role.add_attribute XmlTree::XML::XmlAttribute.new("type", "author")
      org = XmlTree.element("organization")
      org.add_child XmlTree.element("name", model.author)
      parent.add_child XmlTree.element("contributor").add_child(role).add_child(org)
    end

    def items_from_xml(model, value)
      model.items = Array(value).filter_map do |relation|
        el = relation.element_children.first
        next unless el

        if el.unprefixed_name == "relaton-collection"
          Bibcollection.from_xml el.to_xml
        else
          Bibdata.from_xml el.to_xml
        end
      end
    end

    def items_to_xml(model, parent, _doc)
      model.items.each do |item|
        relation = XmlTree.element("relation")
        relation.add_attribute XmlTree::XML::XmlAttribute.new("type", "partOf")
        relation.add_child XmlTree.raw(item.to_xml(model.item_options || {}))
        parent.add_child relation
      end
    end

    private

    def first(value)
      value.is_a?(Array) ? value.first : value
    end

    # @return [Lutaml::Xml::XmlElement, nil] the first child element named
    #   `name`, in any namespace
    def child(element, name)
      element&.element_children&.find { |c| c.unprefixed_name == name }
    end

    # Builds the elements the mapper writes, in the collection namespace.
    module XmlTree
      XML = Lutaml::Xml::DataModel

      module_function

      # @param name [String]
      # @param markup [String, nil] the content: text with inline markup
      # @return [Lutaml::Xml::DataModel::XmlElement]
      def element(name, markup = nil)
        el = XML::XmlElement.new(name, CollectionNamespace)
        markup ? el.add_child(raw(escape(markup))) : el
      end

      # @param xml [String] XML written as it is
      # @return [Lutaml::Xml::DataModel::XmlRawFragment]
      def raw(xml)
        XML::XmlRawFragment.new xml.strip
      end

      # @param element [Lutaml::Xml::XmlElement, nil] a parsed element
      # @return [String, nil] its content, as markup
      def inner_xml(element)
        element&.inner_xml
      end

      # Escapes a bare `&` (plain text from YAML), leaving the XML entity
      # references (`&amp;`, `&lt;`, `&#123;`, `&#x1f;`) and inline markup
      # as they are. An HTML entity (`&nbsp;`) is not defined in XML, so its
      # `&` is escaped too: the fragment parser cannot read it.
      def escape(str)
        str.gsub(/&(?!(?:amp|lt|gt|quot|apos);|#[0-9]+;|#x[0-9a-fA-F]+;)/, "&amp;")
      end
    end
  end
end
