require "relaton/core/processor"

module Relaton
  module Adobe
    # Relaton processor for the Adobe flavor. Registered by
    # Relaton::Registry when the unified gem loads (see
    # lib/relaton/registry.rb). Supports `relaton fetch adobe ...` once
    # the relaton-data-adobe dataset is installed.
    class Processor < Core::Processor
      attr_reader :idtype

      def initialize
        @short = :relaton_adobe
        @prefix = "Adobe"
        @defaultprefix = %r{^(?:Adobe|ATN)}
        @idtype = "Adobe"
      end

      def get(code, date, opts)
        require_relative "../adobe"
        # Delegate to Relaton::Db for cache + index lookup. Once a
        # Bibliography class is added (cf. relaton/iala/bibliography),
        # this should call Bibliography.get directly.
        ::Relaton::Db.instance.fetch("Adobe", code, date, opts)
      end

      def from_xml(xml)
        require_relative "../adobe"
        Item.from_xml xml
      end

      def from_yaml(yaml)
        require_relative "../adobe"
        Item.from_yaml(yaml)
      end

      def grammar_hash
        require_relative "../adobe"
        @grammar_hash ||= ::Relaton::Adobe.grammar_hash
      end

      def remove_index_file
        require_relative "../adobe"
        Relaton::Index.find_or_create(:adobe, url: true, file: "#{INDEXFILE}.yaml").remove_file
      end
    end
  end
end
