require "relaton/core"
module Relaton::Bsi
  class Processor < Relaton::Core::Processor
    def initialize
      @short = :relaton_bsi
      @prefix = "BSI"
      @defaultprefix = %r{^(BSI|BS|PD)\s}
      @idtype = "BSI"
    end

    # @param code [String]
    # @param date [String, nil] year
    # @param opts [Hash]
    # @return [Relaton::Bsi::ItemData]
    def get(code, date, opts)
      require "relaton/bsi"
      ::Relaton::Bsi::Bibliography.get(code, date, opts)
    end

    # @param xml [String]
    # @return [Relaton::Bsi::ItemData]
    def from_xml(xml)
      require "relaton/bsi"
      ::Relaton::Bsi::Item.from_xml xml
    end

    # @param hash [Hash]
    # @return [Relaton::Bsi::ItemData]
    def from_yaml(yaml)
      require "relaton/bsi"
      ::Relaton::Bsi::Item.from_yaml yaml
    end

    # Returns hash of XML grammar
    # @return [String]
    def grammar_hash
      require "relaton/bsi"
      @grammar_hash ||= ::Relaton::Bsi.grammar_hash
    end
  end
end
