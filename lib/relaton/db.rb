require_relative "bib"
require "yaml"
require "net/http"
require "moxml"
require "fileutils"
require "date"

module Relaton
  autoload :Cloud, "relaton/cloud"

  class Db
    # @param global_cache [String] directory of global DB
    # @param local_cache [String] directory of local DB
    def initialize(global_cache, local_cache)
      @registry = Registry.instance
      gpath = global_cache && File.expand_path(global_cache)
      @db = open_cache_biblio(gpath)
      lpath = local_cache && File.expand_path(local_cache)
      @local_db = open_cache_biblio(lpath)
      @queues = {}
      @semaphore = Mutex.new
    end

    # Move global or local caches to anothe dirs
    # @param new_dir [String, nil]
    # @param type: [Symbol]
    # @return [String, nil]
    def mv(new_dir, type: :global)
      case type
      when :global then @db&.mv new_dir
      when :local then @local_db&.mv new_dir
      end
    end

    # Clear global and local databases
    def clear
      @db&.clear
      @local_db&.clear
      @registry.processors.each_value do |p|
        p.remove_index_file if p.respond_to? :remove_index_file
      end
    end

    ##
    # The class of reference requested is determined by the prefix
    # of the reference:
    # GB Standard for gbbib, IETF for ietfbib, ISO for isobib, IEC or IEV for
    #   iecbib,
    #
    # @param text [String] the standard reference to look up (e.g. "ISO 9000")
    # @param year [String] the year the standard was published (optional)
    #
    # @param opts [Hash] options
    # @option opts [Boolean] :all_parts If all-parts reference is required
    # @option opts [Boolean] :keep_year If undated reference should return
    #   actual reference with year
    # @option opts [Integer] :retries (1) Number of network retries
    # @option opts [Boolean] :no_cache If true then don't use cache
    # @option opts [String] :publication_date_before published before this date
    #  (exclusive, formats: "YYYY", "YYYY-MM", or "YYYY-MM-DD")
    # @option opts [String] :publication_date_after published on or
    #  after this date (inclusive, formats: "YYYY", "YYYY-MM",
    #  or "YYYY-MM-DD")
    #
    # @return [nil, RelatonBib::BibliographicItem, ...]
    # @raise [Relaton::UnknownReferenceError] no flavor recognizes the
    #   reference (see Registry#route)
    # @raise [Relaton::NotInLocalStoreError] offline mode, and the local
    #   store has no entry for the reference (relaton#536)
    ##
    def fetch(text, year = nil, opts = {}) # rubocop:disable Metrics/MethodLength
      reference = text.strip
      offline_answer(reference, opts) do |opts| # rubocop:disable Lint/ShadowingOuterLocalVariable
        stdclass, pubid = @registry.route(reference)
        processor = @registry[stdclass]
        ref = if processor.respond_to?(:urn_to_code)
                processor.urn_to_code(reference)&.first
              else reference
              end
        ref ||= reference
        # The routed pubid is the parse of `reference`; a URN rewritten to a
        # code is parsed again by the flavor.
        pubid = nil unless ref == reference
        result = combine_doc ref, year, opts, stdclass
        result || fetch_routed(ref, year, opts, stdclass, pubid)
      end
    end

    # @see Relaton::Db#fetch
    def fetch_db(code, year = nil, opts = {})
      opts[:fetch_db] = true
      fetch code, year, opts
    end

    # fetch all standards from DB
    # @param test [String, nil]
    # @param edition [String], nil
    # @param year [Integer, nil]
    # @return [Array]
    def fetch_all(text = nil, edition: nil, year: nil)
      result = []
      db = @db || @local_db
      if db
        result += db.all do |processor, xml|
          search_xml processor, xml, text, edition, year
        end.compact
      end
      result
    end

    #
    # Fetch asynchronously
    #
    # @param [String] ref reference
    # @param [String] year document yer
    # @param [Hash] opts options
    #
    # @return [RelatonBib::BibliographicItem,
    #   RelatonBib::RequestError, nil] bibitem if document is
    #   found, request error if server doesn't answer,
    #   nil if document not found
    #
    def fetch_async(ref, year = nil, opts = {}, &block) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
      stdclass = async_route ref
      if stdclass
        unless @queues[stdclass]
          processor = @registry[stdclass]
          threads = ENV["RELATON_FETCH_PARALLEL"]&.to_i || processor.threads
          wp = WorkersPool.new(threads) do |args|
            args[3].call fetch(*args[0..2])
          rescue Relaton::RequestError, Relaton::NotInLocalStoreError => e
            args[3].call e
          rescue StandardError => e
            # An unparseable reference ("ISO Standards Tag Set" in a
            # vocabulary corpus) is a not-found input, not a failure: the
            # citation keeps its literal text and the build continues
            # (relaton#412). Real errors keep the ERROR level.
            if unreadable_reference?(e)
              Util.info "`#{args[0]}` -- #{e.message}"
            else
              Util.error "`#{args[0]}` -- #{e.message}"
            end
            args[3].call nil
          rescue Exception => e # rubocop:disable Lint/RescueException
            # The completion callback is a contract: the consumer counts
            # exactly one delivery per fetch, and a missing one blocks it
            # forever (metanorma-standoc CI deadlock, 2026-11-13: an
            # RSpec::Mocks::MockExpectationError -- an Exception, not a
            # StandardError -- escaped the rescue above).
            Util.error "`#{args[0]}` -- #{e.class}: #{e.message}"
            args[3].call nil
          end
          @queues[stdclass] =
            { queue: SizedQueue.new(threads * 2), workers_pool: wp }
          Thread.new { process_queue @queues[stdclass] }
        end
        @queues[stdclass][:queue] << [ref, year, opts, block]
      else yield nil
      end
    end

    #
    # Fetch with the flavor the caller names, else the routed one.
    #
    # @param stdclass [Symbol, String, nil] a processor short name
    #   (`:relaton_iso`, as relaton-cli passes it) or a prefix (`"ISO"`)
    # @raise [Relaton::UnknownReferenceError] no flavor is named and none
    #   recognizes the reference
    #
    # @raise [Relaton::NotInLocalStoreError] offline mode, and the local
    #   store has no entry for the reference (relaton#536)
    #
    def fetch_std(code, year = nil, stdclass = nil, opts = {})
      offline_answer(code, opts) do |opts| # rubocop:disable Lint/ShadowingOuterLocalVariable
        std = named_class(stdclass)
        # A flavor the caller names is the one asked: no co-publisher.
        next check_bibliocache(code, year, opts, std) if std

        std, pubid = @registry.route(code)
        fetch_routed(code, year, opts, std, pubid) ||
          fetch_equivalent(code, year, opts)
      end
    end

    # Cross-SDO equivalence as data: on a total miss, walk the equivalence
    # tables from relaton/equivalence.rb in both directions — a national
    # adoption falls back to the EN, the EN to the ISO, and a base document
    # falls forward to its declared adoptions (.related_for). Each candidate
    # goes through the full routed fetch (cache, co-publishers); an
    # unrouteable candidate is skipped.
    #
    # @return [Relaton::Bib::ItemData, nil]
    def fetch_equivalent(code, year, opts)
      # `relaton/db` alone does not declare the `Relaton::Equivalence`
      # autoload (`relaton.rb` does), so a fetch_std miss NameErrored there.
      require_relative "equivalence"
      Equivalence.related_for(code).each do |candidate|
        Util.info "Not found; trying equivalent `#{candidate}`", key: code
        std, pubid = @registry.route(candidate)
        bib = fetch_routed(candidate, year, opts, std, pubid) and return bib
      rescue UnknownReferenceError
        next
      end
      nil
    end

    # The document identifier class corresponding to the given code
    # @param code [String]
    # @return [Array]
    def docid_type(code)
      stdclass, = @registry.route(code)
      _, code = strip_id_wrapper(code, stdclass)
      [@registry[stdclass].idtype, code]
    rescue UnknownReferenceError
      [nil, code]
    end

    # @param key [String]
    # @return [Hash]
    def load_entry(key)
      (@local_db && @local_db[key]) || @db[key]
    end

    # @param key [String]
    # @param value [String] Bibitem xml serialisation.
    # @option value [String] Bibitem xml serialisation.
    def save_entry(key, value)
      @db.nil? || (@db[key] = value)
      @local_db.nil? || (@local_db[key] = value)
    end

    # list all entries as a serialization
    # @return [String]
    def to_xml
      db = @local_db || @db || return
      parts = db.all.join(" ")
      Moxml.parse(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<documents>#{parts}</documents>",
      ).to_xml(indent: 0, expand_empty: false)
    end

    private

    #
    # Offline mode (Configuration#offline, relaton#536) answers every fetch
    # from the local store only: the block runs with `fetch_db` set, so no
    # path reaches a flavor's `get`, and a miss of the whole resolution
    # (routed flavor, co-publishers, equivalents) raises. An explicit
    # `fetch_db` keeps its nil answer.
    #
    # @yieldparam opts [Hash] the options to fetch with
    # @raise [Relaton::NotInLocalStoreError]
    #
    def offline_answer(reference, opts)
      return yield(opts) if opts[:fetch_db] || !Db.configuration.offline

      yield(opts.merge(fetch_db: true)) or
        raise NotInLocalStoreError.new(reference.to_s,
                                       [@local_db, @db].compact.map(&:dir))
    end

    # True when the error is a flavor's grammar refusing to read the
    # reference. Both are raised by the flavors' pubid/parslet parses; a
    # reference they cannot read is not-found, not a failure (relaton#412).
    def unreadable_reference?(error)
      (defined?(Pubid::Errors::Error) && error.is_a?(Pubid::Errors::Error)) ||
        false
    end

    # The flavor routing picks for `fetch_async`'s per-flavor queue; nil
    # (logged) when no flavor recognizes the reference.
    def async_route(ref)
      @registry.route(ref).first
    rescue UnknownReferenceError => e
      Util.info e.message, key: ref
      nil
    end

    # The processor a caller names by short name (`:relaton_iso`) or prefix.
    def named_class(stdclass)
      return unless stdclass

      short = stdclass.to_sym
      return short if @registry.processors.key?(short)

      @registry.processors.detect { |_, p| p.prefix == stdclass.to_s }&.first
    end

    # The flavor's `get` receives the parsed pubid when there is one
    # (relaton#205), else the String. With `use_api`, api.relaton.org is
    # asked first (relaton#535), and the flavor answers whatever it does not.
    #
    # @param api [Hash] the API tier's state for one fetch: in,
    #   `:stale_etag`/`:stale` (a stale row's ETag and its document, to
    #   revalidate); out, `:etag` (the ETag of an API answer, nil for a
    #   flavor answer), which Db#fetch_entry stores with the row
    def fetch_doc(code, year, opts, processor, query = nil, api: {})
      api_answer(code, year, opts, processor, query, api) ||
        processor.get(query || code, year, opts)
    end

    #
    # The API's document for the query, or nil. The API is asked only for a
    # query that has a pubid cache key, is not all-parts and has no
    # publication date range: the API has no all-parts answer, and a range
    # is not in the key. Its answer is kept only when the document's own
    # cache key is the query's key: the API has no undated or edition logic
    # (`ISO 19115-1` answers the 2014 record), and the flavor's rule for
    # such a query is the one `Db` caches.
    #
    # A stale row the API wrote is revalidated with its ETag. A 304 answers
    # the cached document, fetched today: `Cache#store` reads the row's
    # `fetched` from the document, so the document is stored again, not
    # only its row. It needs no identity check: the row was written from an
    # answer that passed one, for this key.
    #
    def api_answer(code, year, opts, processor, query, api) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/ParameterLists
      api[:etag] = nil
      return unless Db.configuration.use_api
      return if opts[:all_parts] || date_range?(opts)

      key = query && processor.cache_key(code, year, opts, query)
      return unless key.is_a?(::Pubid::Identifier)

      answer = ApiResolver.fetch(processor, key, etag: api[:stale_etag])
      return unless answer
      return revalidated(processor, api, answer, key) if answer.not_modified

      bib = answer.item
      if api_identity?(bib, key, processor)
        api[:etag] = answer.etag
        return bib
      end

      Util.info "api.relaton.org: answered another document " \
                "(#{bib.docidentifier.first&.content}); asking the flavor",
                key: key.to_s
      nil
    end

    # The stale document a 304 kept, fetched today, with its ETag. It is
    # cached data: one that does not read back is a miss (the flavor
    # answers), whatever the model raises for it.
    def revalidated(processor, api, answer, key)
      bib = processor.from_xml api[:stale]
      bib.fetched = Date.today.to_s
      api[:etag] = answer.etag
      bib
    rescue StandardError => e
      Util.info "api.relaton.org: cached document unreadable " \
                "(#{e.class}); asking the flavor", key: key.to_s
      nil
    end

    # The API state Db#fetch_doc starts from: a stale document that the API
    # answered carries the ETag to revalidate it with. Both come from one
    # row of the stale cache (Cache#revalidation), read again here: the
    # stale entry `with_stale` read is not used, since another worker may
    # have replaced the row since, and its ETag would then confirm an older
    # document.
    def api_state(args)
      return {} unless args[:stale].is_a?(String) && args[:stale_db]

      xml, etag = @semaphore.synchronize do
        args[:stale_db].revalidation(args[:id])
      end
      etag ? { stale_etag: etag, stale: xml } : {}
    end

    # The API's document is data: an identifier the flavor cannot key is a
    # mismatch, whatever the key raises for it.
    def api_identity?(bib, key, processor)
      item_key(bib, @registry.processors.key(processor)) == key
    rescue StandardError => e
      Util.info "api.relaton.org: unkeyable answer (#{e.class}); " \
                "asking the flavor", key: key.to_s
      false
    end

    def search_xml(processor, xml, text, edition, year)
      return unless processor
      return unless text.nil? || match_xml_text?(xml, text)

      search_edition_year(processor, xml, edition, year)
    end

    def search_edition_year(processor, content, edition, year) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      item = processor.from_xml(content)
      item if (edition.nil? || item.edition.content == edition) && (year.nil? ||
        item.date.detect do |d|
          d.type == "published" && d.at.to_date.year.to_s == year.to_s
        end)
    end

    def match_xml_text?(xml, text)
      esc = Regexp.escape(text)
      pat = "((?<attr>=((?<apstr>')|\"" \
            "))|>).*?#{esc}" \
            ".*?(?(<attr>)(?(<apstr>)'|\")|<)"
      Regexp.new(pat, Regexp::MULTILINE | Regexp::IGNORECASE)
        .match?(xml)
    end

    def combine_doc(code, year, opts, stdclass) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      return if stdclass == :relaton_bipm

      if (refs = code.split " + ").size > 1
        reltype = "derivedFrom"
        reldesc = nil
      elsif (refs = code.split ", ").size > 1
        reltype = "complements"
        reldesc = Bib::LocalizedMarkedUpString.new content: "amendment"
      else return
      end

      yaml = { docidentifier: [{ content: code }] }.to_yaml
      doc = @registry[stdclass].from_yaml(yaml)
      ref = refs[0]
      updates = check_bibliocache(refs[0], year, opts, stdclass)
      if updates
        doc.relation << Bib::Relation.new(bibitem: updates, type: "updates")
      end
      # The supplement joins its base as the flavor's identifier spells it:
      # `NIST SP 800-38A Add`, not `/Add`, which pubid does not parse.
      divider = %i[relaton_itu relaton_nist].include?(stdclass) ? " " : "/"
      refs[1..].each_with_object(doc) do |c, d|
        bib = check_bibliocache(ref + divider + c, year, opts, stdclass)
        if bib
          d.relation << Bib::Relation.new(
            type: reltype, description: reldesc, bibitem: bib,
          )
        end
      end
      # Nothing resolved: answer not-found, not a stub that holds only the
      # reference (relaton-un#14, metanorma-ietf#205).
      doc.relation.empty? ? nil : doc
    end

    # The legacy string cache key, for a processor with no pubid class. The
    # publication date range is not part of it: it filters, it is not
    # identity.
    def std_id(code, year, opts, stdclass)
      prefix, code = strip_id_wrapper(code, stdclass)
      ret = code
      ret += (stdclass == :relaton_gb ? "-" : ":") + year if year
      ret += " (all parts)" if opts[:all_parts]
      ["#{prefix}(#{ret.strip})", code]
    end

    #
    # The cache key of a query: the flavor's parsed pubid, with the `year`
    # and `all_parts` options folded in. A reference the flavor cannot parse
    # raises `Pubid::Errors::ParseError`. Nil when the flavor has a pubid
    # class but gives no key for this query (a miss by the flavor's own rule,
    # or a query whose answer the cache cannot hold, such as a CCSDS format):
    # that query is not cached. A processor with no pubid class gets the
    # legacy string key.
    #
    # @param pubid [Pubid::Identifier, nil] the reference as routing parsed
    #   it, so the processor does not parse it again
    # @return [Pubid::Identifier, String, nil]
    #
    def cache_key(code, year, opts, stdclass, pubid = nil)
      processor = @registry[stdclass]
      unless processor.pubid_class
        return std_id(code, year, opts, stdclass).first
      end

      processor.cache_key(code, year, opts, pubid)
    end

    #
    # The pubid `get` receives, and the cache key folded from it: one parse
    # of the reference serves both (relaton#205). A processor with no pubid
    # class gets the String and the legacy string key.
    #
    # @param pubid [Pubid::Identifier, nil] routing's parse
    # @return [Array(Pubid::Identifier, Object)] the query pubid (nil: `get`
    #   gets the String) and the key (nil: not cached)
    #
    def query_and_key(code, year, opts, stdclass, pubid)
      processor = @registry[stdclass]
      unless processor.pubid_class
        return [nil, std_id(code, year, opts, stdclass).first]
      end

      query = processor.query_pubid(code, opts, pubid)
      [query, query && processor.cache_key(code, year, opts, query)]
    end

    # The key of a fetched document, from its primary identifier and what
    # that identifier omits (Core::Processor#item_cache_key, relaton#408).
    # The identifier is data, so an unparseable one gives no key.
    def item_key(bib, stdclass)
      docid = bib.docidentifier.detect(&:primary) || bib.docidentifier.first
      return unless docid&.content

      key = cache_key docid.content, nil, {}, stdclass
      return key unless key.is_a? ::Pubid::Identifier

      @registry[stdclass].item_cache_key key, bib
    rescue ::Pubid::Errors::Error
      nil
    end

    def date_range?(opts)
      opts[:publication_date_before] || opts[:publication_date_after]
    end

    def strip_id_wrapper(code, stdclass)
      prefix = @registry[stdclass].prefix
      code =
        if code.is_a?(String)
          code.sub("–", "-").sub(/^#{prefix}\((.+)\)$/, "\\1")
        else code.to_s
        end
      [prefix, code]
    end

    # The routed flavor, then its co-publishers' flavors (relaton#205).
    def fetch_routed(code, year, opts, stdclass, pubid)
      check_bibliocache(code, year, opts, stdclass, pubid: pubid) ||
        copublisher_fetch(code, year, opts, stdclass, pubid)
    end

    #
    # A co-published document the lead flavor's catalog does not have:
    # ask the co-publishers' flavors, in the order the parsed pubid holds
    # them (relaton#205; pubid#469, #472). Each one keys, caches and fetches
    # with its own flavor, so a second fetch is answered from the caches.
    # A co-publisher whose flavor gives no pubid for the lead's printed form
    # is skipped. Only that probe parse is rescued: an error from inside the
    # co-publisher's fetch propagates.
    #
    # @return [Relaton::Bib::ItemData, nil]
    #
    def copublisher_fetch(code, year, opts, stdclass, pubid)
      # The reference as the lead read it: no `PREFIX(...)` wrapper, no en dash.
      _, code = strip_id_wrapper(code, stdclass)
      copublisher_classes(code, opts, stdclass, pubid).each do |publisher, co|
        Util.info "Not found; trying co-publisher `#{publisher}`", key: code
        query = copublisher_query(code, opts, co, publisher) or next
        bib = check_bibliocache(code, year, opts, co, pubid: query)
        return bib if bib
      end
      nil
    end

    # @return [Array<Array(String, Symbol)>] each co-publisher that a flavor
    #   other than the lead serves, with that flavor
    def copublisher_classes(code, opts, stdclass, pubid)
      processor = @registry[stdclass]
      query = processor.query_pubid(code, opts, pubid) or return []

      processor.copublishers(query).filter_map do |publisher|
        co = @registry.class_by_publisher(publisher)
        [publisher, co] if co && co != stdclass
      end.uniq(&:last)
    end

    # The co-publisher flavor's own parse of the reference, or nil when it
    # gives none (a parse error, or a flavor that reads it as a miss: IEEE),
    # which is logged.
    #
    # @return [Pubid::Identifier, nil]
    def copublisher_query(code, opts, stdclass, publisher)
      query = begin
        @registry[stdclass].query_pubid(code, opts)
      rescue ::Pubid::Errors::Error
        nil
      end
      return query if query

      Util.info "Not found; co-publisher `#{publisher}` cannot read it",
                key: code
      nil
    end

    def bib_retval(entry, stdclass)
      @registry[stdclass].from_xml(entry) if entry.is_a?(String)
    end

    def check_bibliocache(code, year, opts, stdclass, pubid: nil) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
      _, searchcode = strip_id_wrapper(code, stdclass)
      query, id = query_and_key(searchcode, year, opts, stdclass, pubid)
      db = id && (@local_db || @db)
      altdb = @local_db && @db ? @db : nil
      if db.nil?
        return if opts[:fetch_db]

        bibentry = new_bib_entry(searchcode, year, opts, stdclass, query: query)
        return bib_retval(bibentry, stdclass)
      end
      if date_range?(opts)
        return check_date_range(searchcode, id, year, opts, stdclass, query)
      end

      # The cache-only path reads, and never expires: a stale entry is
      # still the local store's answer (relaton#536).
      # A document in either cache answers over a not_found in the other.
      if opts[:fetch_db]
        entries = [db, altdb].compact.map { |c| c.read(id) }
        return bib_retval(entries.find { |e| e.is_a?(String) }, stdclass)
      end

      @semaphore.synchronize { replace_stale(db, altdb, id, year) } if altdb
      # The entry new_bib_entry answers, not a second read of `db`: a stale
      # document served from `altdb` has no row in `db`.
      entry = new_bib_entry(searchcode, year, opts, stdclass,
                            db: db, id: id, query: query, altdb: altdb)
      @semaphore.synchronize { replace_stale(altdb, db, id, year) } if altdb
      bib_retval(entry, stdclass)
    end

    # Replace the stale (or missing) row of `id` in `cache` with the valid
    # row `other` holds. A valid row of `cache` is kept (local over global).
    def replace_stale(cache, other, id, year)
      return if cache.valid_entry?(id, year)
      return unless other.valid_entry?(id, year)

      cache.expire id, year
      cache.clone_entry id, other
    end

    #
    # A stale entry (Cache#valid_entry? is false) is refetched, but it is
    # not deleted first: Db#fetch_entry serves it when the refetch fails
    # with a transport error, and replaces it when the refetch answers.
    # With no row of its own, the stale document of the other cache
    # (`altdb:`) is the fallback. `no_cache` asks for a fresh answer, so it
    # has no fallback.
    #
    def new_bib_entry(code, year, opts, stdclass, **args)
      entry, valid = @semaphore.synchronize do
        found = args[:db]&.read(args[:id])
        [found, found && args[:db].valid_entry?(args[:id], year)]
      end
      if !entry || opts[:no_cache] || !valid
        args = with_stale(args, entry) unless opts[:no_cache]
        return fetch_entry(code, year, opts, stdclass, **args)
      end

      if entry.is_a?(NotFound)
        Util.info "not found in cache, if you wish to " \
                  "ignore cache please use `no-cache` option.", key: code
        return
      end
      entry
    end

    # @return [Hash] args, with the `stale:` entry and the `stale_db:` cache
    #   that holds it, when there is one
    def with_stale(args, entry)
      stale_db = args[:db]
      unless entry
        stale_db = args[:altdb]
        entry = @semaphore.synchronize { stale_db&.read(args[:id]) }
        return args unless entry.is_a?(String)
      end
      args.merge(stale: entry, stale_db: stale_db)
    end

    #
    # @option args [String, Relaton::Db::NotFound, nil] :stale the stale
    #   entry of the key: a transport failure answers a stale document with
    #   a warning (relaton#536), and an answer replaces it
    # @option args [Relaton::Db::Cache] :stale_db the cache that holds it
    #
    def fetch_entry(code, year, opts, stdclass, **args) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
      processor = @registry[stdclass]
      api = api_state args
      bib = begin
        net_retry(code, year, opts, processor, opts.fetch(:retries, 1),
                  args[:query], api: api)
      rescue Relaton::RequestError => e
        raise unless args[:stale].is_a?(String)

        Util.warn "#{e.message}; using the cached entry fetched " \
                  "#{args[:stale_db].fetched(args[:id])}", key: code
        return args[:stale]
      end
      entry = bib_entry bib
      return entry if args[:db].nil?

      # `no_cache` refreshes a cached entry, but a failed fetch does not
      # replace a valid cached document with a not-found entry. A stale
      # entry is replaced by any answer; its row goes first, so a dated
      # query's subset row does not outlive the refetch.
      refresh = opts[:no_cache] && bib.respond_to?(:to_xml)
      @semaphore.synchronize do
        args[:db].expire args[:id], year if args[:stale]
        if args[:stale] || refresh || !args[:db].read(args[:id])
          save_bib args[:db], args[:id], bib, entry, stdclass,
                   etag: api[:etag]
        end
      end
      entry
    end

    #
    # Cache a fetched document. The document's own identifier gets a row;
    # when the query key differs from it (an undated or incomplete query),
    # the query gets a row that points to the same document.
    #
    # `etag` is the ETag of the API answer (Db#fetch_doc), nil for a flavor
    # answer.
    def save_bib(db, key, bib, entry, stdclass, etag: nil) # rubocop:disable Metrics/ParameterLists
      item = bib.respond_to?(:docidentifier) && item_key(bib, stdclass)
      db.store key, entry, item_key: item || nil, etag: etag
    end

    #
    # A publication date range selects among editions of the reference. The
    # answer must depend on the citing document's cutoff, never on the order
    # in which parallel workers happen to populate the cache: the edition
    # pool visible to any one worker is whatever earlier workers fetched for
    # their own cutoffs, so answering from that pool is nondeterministic
    # (metanorma#659). A ranged answer is therefore cached under a key that
    # names the range and a hit on it is authoritative; the unqualified
    # query row is never written by a ranged fetch, so it keeps pointing at
    # the latest edition.
    #
    def range_cache_key(key, opts)
      bounds = [opts[:publication_date_before] && "before=#{opts[:publication_date_before]}",
                opts[:publication_date_after] && "after=#{opts[:publication_date_after]}"]
        .compact
      bounds.empty? ? nil : "#{key}@range:#{bounds.join(',')}"
    end

    def check_date_range(code, key, year, opts, stdclass, query = nil)
      qualified = range_cache_key(key, opts)
      unless opts[:no_cache]
        hit = [@local_db, @db].compact.filter_map { |c| c.read(qualified) }.first
        return bib_retval(hit, stdclass) if hit
      end
      return if opts[:fetch_db]

      processor = @registry[stdclass]
      bib = net_retry(code, year, opts, processor, opts.fetch(:retries, 1),
                      query)
      return unless bib.respond_to?(:to_xml)

      entry = bib_entry bib
      item = item_key(bib, stdclass)
      @semaphore.synchronize do
        [@local_db, @db].compact.each do |c|
          # A ranged answer that carries no edition of its own is the
          # undated form: storing it would overwrite the unqualified query
          # row (whose contract is the latest edition), so only a genuinely
          # dated answer may write its own row.
          link = item if item && item != key
          c.store item, entry if link
          c.store qualified, entry, item_key: link if qualified
        end
      end
      bib_retval entry, stdclass
    end

    # @param query [Pubid::Identifier, nil] what `get` receives in place of
    #   the String +code+ (Db#query_and_key)
    # @param api [Hash] the API tier's state (Db#fetch_doc)
    def net_retry(code, year, opts, processor, retries, query = nil, api: {}) # rubocop:disable Metrics/ParameterLists
      fetch_doc code, year, opts, processor, query, api: api
    rescue Relaton::RequestError => e
      raise e unless retries > 1

      net_retry(code, year, opts, processor, retries - 1, query, api: api)
    end

    def bib_entry(bib)
      if bib.respond_to?(:to_xml)
        bib.to_xml(bibdata: true)
      else
        NotFound.new(fetched: Date.today.to_s)
      end
    end

    # @param entry [String] document XML
    # @return [Date, nil] the published date
    def published_date(entry)
      date_str = Moxml.parse(entry)
        .at_xpath("//date[@type='published']/on")&.text
      date_str && parse_pub_date(date_str)
    end

    def pub_date_in_range?(entry, opts) # rubocop:disable Metrics/CyclomaticComplexity
      date = published_date(entry)
      return false unless date

      # `parse_pub_date`, not `Date.parse`: a bound may be "YYYY" or
      # "YYYY-MM", which `Date.parse` rejects.
      after = opts[:publication_date_after]
      return false if after && date < parse_pub_date(after.to_s)

      before = opts[:publication_date_before]
      return false if before && date >= parse_pub_date(before.to_s)

      true
    end

    def parse_pub_date(str)
      case str
      when /^\d{4}-\d{1,2}-\d{1,2}/ then Date.parse(str)
      when /^\d{4}-\d{1,2}/ then Date.strptime(str, "%Y-%m")
      when /^\d{4}/ then Date.strptime(str, "%Y")
      end
    rescue ArgumentError
      nil
    end

    def open_cache_biblio(dir)
      dir && Cache.new(dir)
    end

    def process_queue(qwp)
      while args = qwp[:queue].pop; qwp[:workers_pool] << args end
    end

    class << self
      #
      # Initialse and return relaton instance, with local and global cache names
      #
      # @param local_cache [String, nil] local cache name;
      #   "relaton" created if empty or nil
      # @param global_cache [Boolean, nil] create global_cache if true
      # @param flush_caches [Boolean, nil] flush caches if true
      #
      # @return [Relaton::Db] relaton DB instance
      #
      def init_bib_caches(**opts) # rubocop:disable Metrics/CyclomaticComplexity
        globalname = global_bibliocache_name if opts[:global_cache]
        localname = local_bibliocache_name(opts[:local_cache])
        flush_caches globalname, localname if opts[:flush_caches]
        new(globalname, localname)
      end

      def flush_caches(gcache, lcache)
        FileUtils.rm_rf gcache unless gcache.nil?
        FileUtils.rm_rf lcache unless lcache.nil?
      end

      def global_bibliocache_name
        "#{Dir.home}/.relaton/cache"
      end

      def local_bibliocache_name(cachename)
        return nil if cachename.nil?

        cachename = "relaton" if cachename.empty?
        "#{cachename}/cache"
      end
    end
  end
end

require_relative "db/util"
require_relative "db/config"
require_relative "db/api_resolver"
require_relative "db/workers_pool"
require_relative "db/cache"
require_relative "db/registry"
