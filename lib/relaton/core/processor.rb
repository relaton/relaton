module Relaton
  module Core
    class Processor
      # @rerurn [Symbol]
      attr_reader :short

      # @return [String]
      attr_reader :prefix, :idtype

      # @return [Regexp]
      attr_reader :defaultprefix

      # @return [Array<String>]
      attr_reader :datasets

      # Global document-ID prefixes this flavor owns, e.g. BSI => %w[BS BSI DD …].
      # The source of truth is **pubid**: a flavor sets @pubid_flavor to its Pubid
      # module name (e.g. :Iso) in #initialize, and the prefixes are read from
      # `Pubid::<Flavor>.prefixes` — the SDO's own leading identifier tokens,
      # including non-obvious ones (BSI `DD`) and joint forms (`ISO/IEC`). Flavors
      # with no pubid backing fall back to the single canonical @prefix. Loaded
      # lazily (pubid is only required on first call) and memoized. Feeds the
      # global prefix register (Relaton.prefix_flavor). (relaton-db#103)
      #
      # @return [Array<String>]
      def prefixes
        @prefixes ||= if @pubid_flavor
                        require "pubid"
                        ::Pubid.const_get(@pubid_flavor).prefixes
                      else
                        Array(prefix)
                      end
      end

      def initialize
        raise "This is an abstract class!"
      end

      def get(_code, _date, _opts)
        raise "This is an abstract class!"
      end

      def fetch_data(_source, _opts)
        raise "This is an abstract class!"
      end

      def from_xml(_xml)
        raise "This is an abstract class!"
      end

      def from_yaml(_hash)
        raise "This is an abstract class!"
      end

      def grammar_hash
        raise "This is an abstract class!"
      end

      # Retuns default number of workers. Should be overraded by childred classes if need.
      #
      # @return [Integer] nuber of wokrers
      def threads
        10
      end
    end
  end
end
