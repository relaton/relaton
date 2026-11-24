require_relative "../core/processor"

module Relaton
  module Wmo
    # Relaton processor for the WMO flavor. Registered by
    # Relaton::Registry when the unified gem loads. Supports
    # `relaton fetch wmo ...` once the relaton-data-wmo dataset publishes
    # its index.
    class Processor < Core::Processor
      def initialize
        @short = :relaton_wmo
        @prefix = "WMO"
        # The series heads the grammar carries (pubid#763 + the widening
        # round). Bare S-numbers deliberately lead NO prefix: an S-100
        # lexical form is the shared shape of IHO and WMO, and neither
        # flavor owns the routing (pubid#469).
        @defaultprefix = %r{^(?:WMO-No\.|WMO/TD-No\.|JCOMM|GAW)\s}
        @pubid_identifier = :Wmo # Db cache key
      end

      def get(code, date, opts)
        require_relative "../wmo"
        Bibliography.get(code, date, opts)
      end

      # `Bibliography.get` reads a reference pubid cannot parse as a miss
      # (`pubid_for`), so it gets no key here either: it is not cached.
      def cache_pubid(ref)
        super
      rescue StandardError
        nil
      end

      def from_xml(xml)
        require_relative "../wmo"
        Item.from_xml xml
      end

      def from_yaml(yaml)
        require_relative "../wmo"
        Item.from_yaml(yaml)
      end
    end
  end
end
