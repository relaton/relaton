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

      # The pubid identifier class `Relaton::Db` keys its cache with. Read from
      # @pubid_identifier, else @pubid_flavor. @pubid_identifier exists so a
      # flavor can key its cache with pubid without also sourcing #prefixes
      # from pubid. Nil for a processor with neither: `Db` then keys its cache
      # with the legacy string key.
      #
      # @return [Class, nil]
      def pubid_class
        flavor = @pubid_identifier || @pubid_flavor
        return unless flavor

        require "pubid"
        @pubid_class ||= ::Pubid.const_get(flavor)::Identifier
      end

      # Whether the flavor's identifiers print without a publisher token
      # (OGC `19-025r1`, 3GPP `TS 23.207:REL-18/18.0.0`). Routing then takes
      # an exact parse by the flavor although no prefix of it claims the
      # reference (Registry#route).
      #
      # @return [Boolean]
      def bare_identifiers?
        false
      end

      # Parse a query reference into a pubid. A flavor that normalizes a
      # reference before it parses overrides this. A parse error propagates:
      # an unrecognized reference is not "not found".
      #
      # @param ref [String]
      # @return [Pubid::Identifier, nil]
      def cache_pubid(ref)
        pubid_class&.parse(ref)
      end

      # The reference as `get` receives it and the cache keys it (relaton#205):
      # the parse routing already made, else the flavor's own. Nil when the
      # flavor gives no pubid: `get` then receives the String, and the query
      # is not cached. A flavor overrides this when an option keeps a query
      # out of the cache and away from the pubid (CCSDS format).
      #
      # @param ref [String]
      # @param opts [Hash]
      # @param parsed [Pubid::Identifier, nil] routing's parse, of this
      #   flavor's class
      # @return [Pubid::Identifier, nil]
      def query_pubid(ref, _opts = {}, parsed = nil)
        pubid = parsed || cache_pubid(ref)
        # A flavor that reads an unparseable reference as a miss (IANA,
        # IEEE) gives nil or the raw String: no pubid then. The nil test comes
        # first: without a pubid class, pubid may not be loaded.
        pubid if !pubid.nil? && pubid.is_a?(::Pubid::Identifier)
      end

      # The publishers of a co-published identifier after the lead, in the
      # order the parsed pubid holds them: the printed order (pubid#472).
      # Relaton::Db asks their flavors when the lead's catalog has no record
      # (relaton#205). A flavor whose pubid keeps them elsewhere overrides
      # this (IEEE).
      #
      # @param pubid [Pubid::Identifier] the query pubid (#query_pubid)
      # @return [Array<String>] publisher abbreviations, e.g. `["IEC"]`
      def copublishers(pubid)
        pubid = pubid.identifiers.first if pubid.all_parts?
        return [] unless pubid.respond_to?(:copublishers)

        Array(pubid.copublishers).map(&:to_s)
      end

      # Set the year on a parsed pubid, where the flavor's `get` applies it. The
      # default sets the identifier's own year. A flavor whose `get` applies
      # the year elsewhere overrides this (see #fold_year_on_root).
      #
      # @param pubid [Pubid::Identifier]
      # @param year [String, Integer]
      # @return [Pubid::Identifier]
      def fold_year(pubid, year)
        pubid.class.from_hash pubid.to_hash.merge("year" => year.to_s)
      end

      # Set the year on the document the identifier names (`#root`): the base
      # document of a supplement, the adopted document of an adoption. For a
      # flavor whose `get` applies the year there (ISO, CEN, BSI).
      #
      # @param pubid [Pubid::Identifier]
      # @param year [String, Integer]
      # @return [Pubid::Identifier]
      def fold_year_on_root(pubid, year)
        copy = pubid.class.from_hash pubid.to_hash
        copy.root.date = ::Pubid::Components::Date.new(year: year.to_s)
        copy
      end

      # The cache key for a query: the parsed pubid with the `year` and
      # `all_parts` options folded in. The publication date range is not part
      # of the identity, so it never enters the key.
      #
      # @param ref [String]
      # @param year [String, Integer, nil]
      # @param opts [Hash]
      # @param parsed [Pubid::Identifier, nil] the reference as already parsed
      #   with this flavor's class (#query_pubid); parsed here otherwise
      # @return [Pubid::Identifier, nil] never the given object itself when a
      #   year or all-parts is folded in: those fold on copies
      def cache_key(ref, year, opts, parsed = nil)
        pubid = query_pubid(ref, opts, parsed) or return

        pubid = fold_year(pubid, year) if year
        pubid = pubid.to_all_parts if opts[:all_parts] && !pubid.all_parts?
        pubid
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
