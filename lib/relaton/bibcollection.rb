module Relaton
  # A Relaton collection: a title, an author, a doctype and a list of items,
  # where an item is a bibliographic item (`Relaton::Bibdata`) or a nested
  # collection.
  #
  # The XML is read and written by the lutaml-model mapper
  # `Relaton::CollectionXml` (relaton#459), as `Relaton::Bib::Item` maps
  # `Relaton::Bib::ItemData`. The YAML (`#to_h`, `{"root" => …}`) is the
  # format `Relaton::Cli::CollectionStore` keeps on disk, unchanged.
  class Bibcollection
    ATTRIBS = %i[title items doctype author].freeze

    attr_accessor :title, :doctype, :author

    # Options of `#to_xml` that `CollectionXml` hands to the items.
    attr_accessor :item_options

    # @param options [Hash] the collection's attributes, with String or
    #   Symbol keys; an item is a Hash, a bibliographic item, a
    #   `Relaton::Bibdata` or a `Relaton::Bibcollection`
    def initialize(options = {})
      options ||= {}
      ATTRIBS.each do |k|
        send "#{k}=", options.key?(k) ? options[k] : options[k.to_s]
      end
    end

    # @param source [String, #to_xml] Relaton collection XML, or a parsed
    #   document that answers `to_xml`
    # @return [Relaton::Bibcollection]
    def self.from_xml(source)
      source = source.to_xml unless source.is_a?(String)
      CollectionXml.from_xml source
    end

    def items
      @items ||= []
    end

    # @param value [Array<Hash, Relaton::Bibdata, Relaton::Bibcollection>, nil]
    def items=(value)
      @items = (value || []).map { |item| new_bib_item_class item }
    end

    # arbitrary number, must sort after all bib items
    def doc_number
      9999999
    end

    # Add a dcoument to the collection
    # @param item [RelatonBib::BibliographicItem]
    def <<(item)
      items << new_bib_item_class(item)
    end

    # @param opts [Hash] options for the items' `to_xml`
    # @return [String] XML
    def to_xml(opts = {})
      items.sort_by!(&:doc_number)
      self.item_options = opts.select { |k, _| k.is_a? Symbol }
      CollectionXml.to_xml self
    end

    # @param item [Hash, RelatonBib::BibliographicItem, Relatin::Bibdata,
    #   Relaton::Bibcollection]
    # @return [Relaton::Bibdata, Relaton::Bibcollection]
    def new_bib_item_class(item) # rubocop:disable Metrics/MethodLength
      if item.is_a?(Hash)
        # `#to_h` writes a nested collection as `{"root" => …}`.
        if item["root"].is_a?(Hash)
          ::Relaton::Bibcollection.new(item["root"])
        elsif item["items"]
          ::Relaton::Bibcollection.new(item)
        else
          bibitem = ::Relaton::Cli::YAMLConvertor.convert_single_file item
          ::Relaton::Bibdata.new bibitem
        end
      elsif item.is_a?(Relaton::Bibdata) || item.is_a?(Relaton::Bibcollection)
        item
      else ::Relaton::Bibdata.new(item)
      end
    end

    def items_flattened
      items.sort_by!(&:doc_number)

      items.reduce([]) do |acc, item|
        acc << if item.is_a? ::Relaton::Bibcollection
                 item.items_flattened
               else
                 item
               end
      end
    end

    def to_yaml
      to_h.to_yaml
    end

    def to_h
      items.sort_by!(&:doc_number)

      a = ATTRIBS.each_with_object({}) { |k, acc| acc[k.to_s] = send(k) }
      a["items"] = a["items"].map(&:to_h)

      { "root" => a }
    end
  end
end

require_relative "collection_xml"
