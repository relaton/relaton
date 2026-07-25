require "relaton/core/processor"

module Relaton
  module Easc
    # Relaton processor for the EASC flavor. Registered by
    # Relaton::Db::Registry when the unified gem loads (see
    # lib/relaton/db/registry.rb). Supports `relaton fetch easc ...`
    # once the relaton-data-easc dataset is installed.
    class Processor < Core::Processor
      attr_reader :idtype

      def initialize
        @short = :relaton_easc
        @prefix = "EASC"
        # Both Cyrillic and Latin series prefixes route here.
        @defaultprefix = %r{^(?:ПМГ|РМГ|PMG|RMG)\b}
        @idtype = "EASC"
      end

      def get(code, date, opts)
        require_relative "../easc"
        ::Relaton::Db.instance.fetch("EASC", code, date, opts)
      end

      def from_xml(xml)
        require_relative "../easc"
        Item.from_xml xml
      end

      def from_yaml(yaml)
        require_relative "../easc"
        Item.from_yaml(yaml)
      end

      def grammar_hash
        require_relative "../easc"
        @grammar_hash ||= ::Relaton::Easc.grammar_hash
      end

      def remove_index_file
        require_relative "../easc"
        Relaton::Index.find_or_create(:easc, url: true, file: "#{INDEXFILE}.yaml").remove_file
      end
    end
  end
end
