require "relaton/bib"
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
    ##
    def fetch(text, year = nil, opts = {}) # rubocop:disable Metrics/MethodLength
      reference = text.strip
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
      result || check_bibliocache(ref, year, opts, stdclass, pubid: pubid)
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
          rescue Relaton::RequestError => e
            args[3].call e
          rescue StandardError => e
            Util.error "`#{args[0]}` -- #{e.message}"
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
    def fetch_std(code, year = nil, stdclass = nil, opts = {})
      std = named_class(stdclass) || @registry.route(code).first
      check_bibliocache(code, year, opts, std)
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

    def fetch_doc(code, year, opts, processor)
      if Db.configuration.use_api then fetch_api(code, year, opts, processor)
      else processor.get(code, year, opts)
      end
    end

    def fetch_api(code, year, opts, processor)
      url = "#{Db.configuration.api_host}" \
            "/api/v1/document?#{params(code, year, opts)}"
      rsp = Net::HTTP.get_response URI(url)
      processor.from_xml rsp.body if rsp.code == "200"
    rescue Errno::ECONNREFUSED
      processor.get(code, year, opts)
    end

    def params(code, year, opts)
      opts.merge(code: code, year: year).map { |k, v| "#{k}=#{v}" }.join "&"
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

    # The key of a fetched document, from its primary identifier. The
    # identifier is data, so an unparseable one gives no key.
    def item_key(bib, stdclass)
      docid = bib.docidentifier.detect(&:primary) || bib.docidentifier.first
      return unless docid&.content

      cache_key docid.content, nil, {}, stdclass
    rescue ::Pubid::Errors::Error, Parslet::ParseFailed
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

    def bib_retval(entry, stdclass)
      if entry && !entry.match?(/^not_found/)
        @registry[stdclass].from_xml(entry)
      end
    end

    def check_bibliocache(code, year, opts, stdclass, pubid: nil) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
      _, searchcode = strip_id_wrapper(code, stdclass)
      id = cache_key(searchcode, year, opts, stdclass, pubid)
      db = id && (@local_db || @db)
      altdb = @local_db && @db ? @db : nil
      if db.nil?
        return if opts[:fetch_db]

        bibentry = new_bib_entry(searchcode, year, opts, stdclass)
        return bib_retval(bibentry, stdclass)
      end
      if date_range?(opts)
        return check_date_range(searchcode, id, year, opts, stdclass)
      end

      @semaphore.synchronize { db.expire id, year }
      if altdb
        return bib_retval(altdb[id], stdclass) if opts[:fetch_db]

        @semaphore.synchronize do
          db.clone_entry id, altdb if altdb.valid_entry? id, year
        end
        new_bib_entry(searchcode, year, opts, stdclass, db: db, id: id)
        @semaphore.synchronize do
          altdb.clone_entry(id, db) if !altdb.valid_entry?(id, year)
        end
      else
        return bib_retval(db[id], stdclass) if opts[:fetch_db]

        new_bib_entry(searchcode, year, opts, stdclass, db: db, id: id)
      end
      bib_retval(db[id], stdclass)
    end

    def new_bib_entry(code, year, opts, stdclass, **args)
      entry = @semaphore.synchronize { args[:db] && args[:db][args[:id]] }
      if !entry || opts[:no_cache]
        return fetch_entry(code, year, opts, stdclass, **args)
      end

      if entry&.match?(/^not_found/)
        Util.info "not found in cache, if you wish to " \
                  "ignore cache please use `no-cache` option.", key: code
        return
      end
      entry
    end

    def fetch_entry(code, year, opts, stdclass, **args) # rubocop:disable Metrics/AbcSize
      processor = @registry[stdclass]
      bib = net_retry(code, year, opts, processor, opts.fetch(:retries, 1))
      entry = bib_entry bib
      return entry if args[:db].nil?

      # `no_cache` refreshes a cached entry, but a failed fetch does not
      # replace a cached document with `not_found`.
      refresh = opts[:no_cache] && bib.respond_to?(:to_xml)
      @semaphore.synchronize do
        if refresh || !args[:db][args[:id]]
          save_bib args[:db], args[:id], bib, entry, stdclass
        end
      end
      entry
    end

    #
    # Cache a fetched document. The document's own identifier gets a row;
    # when the query key differs from it (an undated or incomplete query),
    # the query gets a row that points to the same document.
    #
    def save_bib(db, key, bib, entry, stdclass)
      item = bib.respond_to?(:docidentifier) && item_key(bib, stdclass)
      db.store key, entry, item_key: item || nil
    end

    #
    # A publication date range selects among the cached editions of the
    # reference, so it is not part of the key. On a miss the flavor is asked
    # with the range, and its answer is cached under its own identifier only:
    # the query row keeps pointing to the latest edition.
    #
    def check_date_range(code, key, year, opts, stdclass) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      caches = [@local_db, @db].compact
      cached = caches.flat_map { |c| c.candidates(key) }.filter_map do |_, xml|
        date = published_date(xml)
        [date, xml] if date && pub_date_in_range?(xml, opts)
      end.max_by(&:first)
      return bib_retval(cached.last, stdclass) if cached && !opts[:no_cache]
      return if opts[:fetch_db]

      processor = @registry[stdclass]
      bib = net_retry(code, year, opts, processor, opts.fetch(:retries, 1))
      return unless bib.respond_to?(:to_xml)

      entry = bib_entry bib
      item = item_key(bib, stdclass)
      if item
        @semaphore.synchronize do
          [@local_db, @db].compact.each { |c| c.store item, entry }
        end
      end
      bib_retval entry, stdclass
    end

    def net_retry(code, year, opts, processor, retries)
      fetch_doc code, year, opts, processor
    rescue Relaton::RequestError => e
      raise e unless retries > 1

      net_retry(code, year, opts, processor, retries - 1)
    end

    def bib_entry(bib)
      if bib.respond_to?(:to_xml)
        bib.to_xml(bibdata: true)
      else
        "not_found #{Date.today}"
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
require_relative "db/workers_pool"
require_relative "db/cache"
require_relative "db/registry"
