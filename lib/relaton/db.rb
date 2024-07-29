module Relaton
  class Db
    # @param global_cache [String] directory of global DB
    # @param local_cache [String] directory of local DB
    def initialize(global_cache, local_cache)
      @registry = Relaton::Registry.instance
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
        require p.short.to_s
        p.remove_index_file if p.respond_to? :remove_index_file
      end
    end

    ##
    # The class of reference requested is determined by the prefix of the reference:
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
    #
    # @return [nil, RelatonBib::BibliographicItem,
    #   RelatonIsoBib::IsoBibliographicItem, RelatonItu::ItuBibliographicItem,
    #   RelatonIetf::IetfBibliographicItem, RelatonIec::IecBibliographicItem,
    #   RelatonIeee::IeeeBibliographicItem, RelatonNist::NistBibliongraphicItem,
    #   RelatonGb::GbbibliographicItem, RelatonOgc::OgcBibliographicItem,
    #   RelatonCalconnect::CcBibliographicItem, RelatinUn::UnBibliographicItem,
    #   RelatonBipm::BipmBibliographicItem, RelatonIho::IhoBibliographicItem,
    #   RelatonOmg::OmgBibliographicItem, RelatonW3c::W3cBibliographicItem]
    ##
    def fetch(text, year = nil, opts = {})
      reference = text.strip
      stdclass = @registry.class_by_ref(reference) || return
      processor = @registry[stdclass]
      ref = if processor.respond_to?(:urn_to_code)
              processor.urn_to_code(reference)&.first
            else reference
            end
      ref ||= reference
      result = combine_doc ref, year, opts, stdclass
      result || check_bibliocache(ref, year, opts, stdclass)
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
        result += db.all do |file, xml|
          search_xml file, xml, text, edition, year
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
    # @return [RelatonBib::BibliographicItem, RelatonBib::RequestError, nil] bibitem if document is found,
    #   request error if server doesn't answer, nil if document not found
    #
    def fetch_async(ref, year = nil, opts = {}, &block) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
      stdclass = @registry.class_by_ref ref
      if stdclass
        unless @queues[stdclass]
          processor = @registry[stdclass]
          threads = ENV["RELATON_FETCH_PARALLEL"]&.to_i || processor.threads
          wp = WorkersPool.new(threads) do |args|
            args[3].call fetch(*args[0..2])
          rescue RelatonBib::RequestError => e
            args[3].call e
          rescue StandardError => e
            Util.error "`#{args[0]}` -- #{e.message}"
            args[3].call nil
          end
          @queues[stdclass] = { queue: SizedQueue.new(threads * 2), workers_pool: wp }
          Thread.new { process_queue @queues[stdclass] }
        end
        @queues[stdclass][:queue] << [ref, year, opts, block]
      else yield nil
      end
    end

    # @param code [String]
    # @param year [String, NilClass]
    # @param stdclass [Symbol, NilClass]
    #
    # @param opts [Hash]
    # @option opts [Boolean] :all_parts If all-parts reference is required
    # @option opts [Boolean] :keep_year If undated reference should return
    #   actual reference with year
    # @option opts [Integer] :retries (1) Number of network retries
    #
    # @return [nil, RelatonBib::BibliographicItem,
    #   RelatonIsoBib::IsoBibliographicItem, RelatonItu::ItuBibliographicItem,
    #   RelatonIetf::IetfBibliographicItem, RelatonIec::IecBibliographicItem,
    #   RelatonIeee::IeeeBibliographicItem, RelatonNist::NistBibliongraphicItem,
    #   RelatonGb::GbbibliographicItem, RelatonOgc::OgcBibliographicItem,
    #   RelatonCalconnect::CcBibliographicItem, RelatinUn::UnBibliographicItem,
    #   RelatonBipm::BipmBibliographicItem, RelatonIho::IhoBibliographicItem,
    #   RelatonOmg::OmgBibliographicItem, RelatonW3c::W3cBibliographicItem]
    def fetch_std(code, year = nil, stdclass = nil, opts = {})
      std = nil
      @registry.processors.each do |name, processor|
        std = name if processor.prefix == stdclass
      end
      std = @registry.class_by_ref(code) or return nil unless std

      check_bibliocache(code, year, opts, std)
    end

    # The document identifier class corresponding to the given code
    # @param code [String]
    # @return [Array]
    def docid_type(code)
      stdclass = @registry.class_by_ref(code) or return [nil, code]
      _, code = strip_id_wrapper(code, stdclass)
      [@registry[stdclass].idtype, code]
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
      Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
        xml.documents { xml.parent.add_child db.all.join(" ") }
      end.to_xml
    end

    private

    # @param (see #fetch_api)
    # @return (see #fetch_api)
    def fetch_doc(code, year, opts, processor)
      if Relaton.configuration.use_api then fetch_api(code, year, opts, processor)
      else processor.get(code, year, opts)
      end
    end

    #
    # @param code [String]
    # @param year [String]
    #
    # @param opts [Hash]
    # @option opts [Boolean] :all_parts If all-parts reference is required
    # @option opts [Boolean] :keep_year If undated reference should return
    #   actual reference with year
    #
    # @param processor [Relaton::Processor]
    # @return [RelatonBib::BibliographicItem, nil]
    def fetch_api(code, year, opts, processor)
      url = "#{Relaton.configuration.api_host}/api/v1/document?#{params(code, year, opts)}"
      rsp = Net::HTTP.get_response URI(url)
      processor.from_xml rsp.body if rsp.code == "200"
    rescue Errno::ECONNREFUSED
      processor.get(code, year, opts)
    end

    #
    # Make string of parametrs
    #
    # @param [String] code
    # @param [String] year
    # @param [Hash] opts
    #
    # @return [String]
    #
    def params(code, year, opts)
      opts.merge(code: code, year: year).map { |k, v| "#{k}=#{v}" }.join "&"
    end

    # @param file [String] file path
    # @param xml [String] content in XML format
    # @param text [String, nil] text to serach
    # @param edition [String, nil] edition to filter
    # @param year [Integer, nil] year to filter
    # @return [BibliographicItem, nil]
    def search_xml(file, xml, text, edition, year)
      return unless text.nil? || match_xml_text(xml, text)

      search_edition_year(file, xml, edition, year)
    end

    # @param file [String] file path
    # @param content [String] content in XML or YAML format
    # @param edition [String, nil] edition to filter
    # @param year [Integer, nil] year to filter
    # @return [BibliographicItem, nil]
    def search_edition_year(file, content, edition, year) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      processor = @registry.processor_by_ref(file.split("/")[-2])
      item = if file.match?(/xml$/) then processor.from_xml(content)
             else processor.hash_to_bib(YAML.safe_load(content))
             end
      item if (edition.nil? || item.edition.content == edition) && (year.nil? ||
        item.date.detect { |d| d.type == "published" && d.on(:year).to_s == year.to_s })
    end

    #
    # Look up text in the XML elements attributes and content
    #
    # @param xml [String] content in XML format
    # @param text [String, nil] text to serach
    #
    # @return [Boolean]
    #
    def match_xml_text(xml, text)
      %r{((?<attr>=((?<apstr>')|"))|>).*?#{text}.*?(?(<attr>)(?(<apstr>)'|")|<)}mi.match?(xml)
    end

    # @param code [String]
    # @param year [String, nil]
    # @param stdslass [String]
    #
    # @param opts [Hash] options
    # @option opts [Boolean] :all_parts If all-parts reference is required
    # @option opts [Boolean] :keep_year If undated reference should return
    #   actual reference with year
    # @option opts [Integer] :retries (1) Number of network retries
    #
    # @return [nil, RelatonBib::BibliographicItem,
    #   RelatonIsoBib::IsoBibliographicItem, RelatonItu::ItuBibliographicItem,
    #   RelatonIetf::IetfBibliographicItem, RelatonIec::IecBibliographicItem,
    #   RelatonIeee::IeeeBibliographicItem, RelatonNist::NistBibliongraphicItem,
    #   RelatonGb::GbbibliographicItem, RelatonOgc::OgcBibliographicItem,
    #   RelatonCalconnect::CcBibliographicItem, RelatinUn::UnBibliographicItem,
    #   RelatonBipm::BipmBibliographicItem, RelatonIho::IhoBibliographicItem,
    #   RelatonOmg::OmgBibliographicItem, RelatonW3c::W3cBibliographicItem]
    def combine_doc(code, year, opts, stdclass) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      return if stdclass == :relaton_bipm

      if (refs = code.split " + ").size > 1
        reltype = "derivedFrom"
        reldesc = nil
      elsif (refs = code.split ", ").size > 1
        reltype = "complements"
        reldesc = RelatonBib::FormattedString.new content: "amendment"
      else return
      end

      doc = @registry[stdclass].hash_to_bib docid: { id: code }
      ref = refs[0]
      updates = check_bibliocache(refs[0], year, opts, stdclass)
      if updates
        doc.relation << RelatonBib::DocumentRelation.new(bibitem: updates, type: "updates")
      end
      divider = stdclass == :relaton_itu ? " " : "/"
      refs[1..].each_with_object(doc) do |c, d|
        bib = check_bibliocache(ref + divider + c, year, opts, stdclass)
        if bib
          d.relation << RelatonBib::DocumentRelation.new(
            type: reltype, description: reldesc, bibitem: bib,
          )
        end
      end
    end

    # TODO: i18n
    # Fofmat ID
    # @param code [String]
    # @param year [String]
    #
    # @param opts [Hash]
    # @option opts [Boolean] :all_parts If all-parts reference is required
    # @option opts [Boolean] :keep_year If undated reference should return
    #   actual reference with year
    # @option opts [Integer] :retries (1) Number of network retries
    #
    # @param stdClass [Symbol]
    # @return [Array<String>] docid and code
    def std_id(code, year, opts, stdclass)
      prefix, code = strip_id_wrapper(code, stdclass)
      ret = code
      ret += (stdclass == :relaton_gb ? "-" : ":") + year if year
      ret += " (all parts)" if opts[:all_parts]
      ["#{prefix}(#{ret.strip})", code]
    end

    # Find prefix and clean code
    # @param code [String]
    # @param stdClass [Symbol]
    # @return [Array]
    def strip_id_wrapper(code, stdclass)
      prefix = @registry[stdclass].prefix
      code = code.sub(/\u2013/, "-").sub(/^#{prefix}\((.+)\)$/, "\\1")
      [prefix, code]
    end

    #
    # @param entry [String, nil] XML string
    # @param stdclass [Symbol]
    #
    # @return [nil, RelatonBib::BibliographicItem,
    #   RelatonIsoBib::IsoBibliographicItem, RelatonItu::ItuBibliographicItem,
    #   RelatonIetf::IetfBibliographicItem, RelatonIec::IecBibliographicItem,
    #   RelatonIeee::IeeeBibliographicItem, RelatonNist::NistBibliongraphicItem,
    #   RelatonGb::GbbibliographicItem, RelatonOgc::OgcBibliographicItem,
    #   RelatonCalconnect::CcBibliographicItem, RelatinUn::UnBibliographicItem,
    #   RelatonBipm::BipmBibliographicItem, RelatonIho::IhoBibliographicItem,
    #   RelatonOmg::OmgBibliographicItem, RelatonW3c::W3cBibliographicItem]
    def bib_retval(entry, stdclass)
      if entry && !entry.match?(/^not_found/)
        @registry[stdclass].from_xml(entry)
      end
    end

    # @param code [String]
    # @param year [String]
    #
    # @param opts [Hash]
    # @option opts [Boolean] :all_parts If all-parts reference is required
    # @option opts [Boolean] :keep_year If undated reference should return
    #   actual reference with year
    # @option opts [Integer] :retries (1) Number of network retries
    #
    # @param stdclass [Symbol]
    # @return [nil, RelatonBib::BibliographicItem,
    #   RelatonIsoBib::IsoBibliographicItem, RelatonItu::ItuBibliographicItem,
    #   RelatonIetf::IetfBibliographicItem, RelatonIec::IecBibliographicItem,
    #   RelatonIeee::IeeeBibliographicItem, RelatonNist::NistBibliongraphicItem,
    #   RelatonGb::GbbibliographicItem, RelatonOgc::OgcBibliographicItem,
    #   RelatonCalconnect::CcBibliographicItem, RelatinUn::UnBibliographicItem,
    #   RelatonBipm::BipmBibliographicItem, RelatonIho::IhoBibliographicItem,
    #   RelatonOmg::OmgBibliographicItem, RelatonW3c::W3cBibliographicItem]
    def check_bibliocache(code, year, opts, stdclass) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
      id, searchcode = std_id(code, year, opts, stdclass)
      db = @local_db || @db
      altdb = @local_db && @db ? @db : nil
      if db.nil?
        return if opts[:fetch_db]

        bibentry = new_bib_entry(searchcode, year, opts, stdclass)
        return bib_retval(bibentry, stdclass)
      end

      @semaphore.synchronize do
        db.delete(id) unless db.valid_entry?(id, year)
      end
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

    #
    # Create new bibliographic entry if it doesn't exist in database
    #
    # @param code [String]
    # @param year [String]
    #
    # @param opts [Hash]
    # @option opts [Boolean, nil] :all_parts If true then all-parts reference is
    #   requested
    # @option opts [Boolean, nil] :keep_year If true then undated reference
    #   should return actual reference with year
    # @option opts [Integer] :retries (1) Number of network retries
    # @option opts [Boolean] :no_cache If true then don't use cache
    #
    # @param stdclass [Symbol]
    # @param db [Relaton::DbCache,`nil]
    # @param id [String, nil] docid
    #
    # @return [String] bibliographic entry
    #   XML or "redirection ID" or "not_found YYYY-MM-DD" string
    #
    def new_bib_entry(code, year, opts, stdclass, **args)
      entry = @semaphore.synchronize { args[:db] && args[:db][args[:id]] }
      return fetch_entry(code, year, opts, stdclass, **args) if !entry || opts[:no_cache]

      if entry&.match?(/^not_found/)
        Util.info "not found in cache, if you wish to " \
                  "ignore cache please use `no-cache` option.", key: code
        return
      end
      entry
    end

    def fetch_entry(code, year, opts, stdclass, **args)
      processor = @registry[stdclass]
      bib = net_retry(code, year, opts, processor, opts.fetch(:retries, 1))

      entry = check_entry(bib, stdclass, **args)
      return entry if args[:db].nil?

      @semaphore.synchronize { args[:db][args[:id]] ||= entry }
      args[:no_cache] ? bib_entry(bib) : entry
    end

    #
    # If the reference isn't equal to the document identifier
    # then store the document in the cache and create for the reference a redirection to the document
    #
    # @param [<Type>] bib <description>
    # @param [<Type>] stdclass <description>
    # @param [<Type>] **args <description>
    #
    # @return [<Type>] <description>
    #
    def check_entry(bib, stdclass, **args) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      bib_id = bib&.docidentifier&.first&.id

      # when ref isn't equal to bib's id then return a redirection to bib's id
      if args[:db] && args[:id] && bib_id && args[:id] !~ %r{#{Regexp.quote("(#{bib_id})")}}
        bid = std_id(bib.docidentifier.first.id, nil, {}, stdclass).first
        @semaphore.synchronize { args[:db][bid] ||= bib_entry bib }
        "redirection #{bid}"
      else bib_entry bib
      end
    end

    #
    # @param code [String]
    # @param year [String]
    #
    # @param opts [Hash]
    # @option opts [Boolean] :all_parts If all-parts reference is required
    # @option opts [Boolean] :keep_year If undated reference should return
    #   actual reference with year
    #
    # @param processor [Relaton::Processor]
    # @param retries [Integer] remain Number of network retries
    #
    # @raise [RelatonBib::RequestError]
    # @return [RelatonBib::BibliographicItem]
    #
    def net_retry(code, year, opts, processor, retries)
      fetch_doc code, year, opts, processor
    rescue RelatonBib::RequestError => e
      raise e unless retries > 1

      net_retry(code, year, opts, processor, retries - 1)
    end

    # @param bib [RelatonBib::BibliographicItem,
    #   RelatonIsoBib::IsoBibliographicItem, RelatonItu::ItuBibliographicItem,
    #   RelatonIetf::IetfBibliographicItem, RelatonIec::IecBibliographicItem,
    #   RelatonIeee::IeeeBibliographicItem, RelatonNist::NistBibliongraphicItem,
    #   RelatonGb::GbbibliographicItem, RelatonOgc::OgcBibliographicItem,
    #   RelatonCalconnect::CcBibliographicItem, RelatinUn::UnBibliographicItem,
    #   RelatonBipm::BipmBibliographicItem, RelatonIho::IhoBibliographicItem,
    #   RelatonOmg::OmgBibliographicItem, RelatonW3c::W3cBibliographicItem]
    # @return [String] XML or "not_found mm-dd-yyyy"
    def bib_entry(bib)
      bib.respond_to?(:to_xml) ? bib.to_xml(bibdata: true) : "not_found #{Date.today}"
    end

    # @param dir [String, nil] DB directory
    # @return [Relaton::DbCache, NilClass]
    def open_cache_biblio(dir) # rubocop:disable Metrics/MethodLength
      return nil if dir.nil?

      db = DbCache.new dir

      Dir["#{dir}/*/"].each do |fdir|
        next if db.check_version?(fdir)

        FileUtils.rm_rf(fdir, secure: true)
        Util.info "cache #{fdir}: version is obsolete and cache is cleared."
      end
      db
    end

    # @param qwp [Hash]
    # @option qwp [Queue] :queue The queue of references to fetch
    # @option qwp [Relaton::WorkersPool] :workers_pool The pool of workers
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
        Relaton::Db.new(globalname, localname)
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
