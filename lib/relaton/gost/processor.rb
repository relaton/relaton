require "relaton/core/processor"

module Relaton
  module Gost
    # Relaton processor for the GOST flavor. Registered by
    # Relaton::Db::Registry when the unified gem loads (see
    # lib/relaton/db/registry.rb). Supports `relaton fetch gost ...`
    # once the relaton-data-gost dataset is installed.
    class Processor < Core::Processor
      attr_reader :idtype

      def initialize
        @short = :relaton_gost
        @prefix = "GOST"
        # Both Latin "GOST" and Cyrillic "ГОСТ" route here. The trailing
        # \b keeps the prefix from swallowing longer tokens ("GOSTA …").
        @defaultprefix = %r{^(?:GOST|ГОСТ)\b}
        @idtype = "GOST"
      end

      def get(code, date, opts)
        require_relative "../gost"
        Bibliography.get(code, date, opts)
      end

      def from_xml(xml)
        require_relative "../gost"
        Item.from_xml xml
      end

      def from_yaml(yaml)
        require_relative "../gost"
        Item.from_yaml(yaml)
      end

      def grammar_hash
        require_relative "../gost"
        @grammar_hash ||= ::Relaton::Gost.grammar_hash
      end

      def remove_index_file
        require_relative "../gost"
        Relaton::Index.find_or_create(:gost, url: true, file: "#{INDEXFILE}.yaml").remove_file
      end
    end
  end
end
