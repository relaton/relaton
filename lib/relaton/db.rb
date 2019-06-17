# require "pstore"
require_relative "registry"
require_relative "db_cache"

module Relaton
  class RelatonError < StandardError; end

  class Db
    SUPPORTED_GEMS = %w[relaton_iso relaton_ietf relaton_gb relaton_iec relaton_nist].freeze

    # @param global_cache [String] directory of global DB
    # @param local_cache [String] directory of local DB
    def initialize(global_cache, local_cache)
      register_gems
      @registry = Relaton::Registry.instance
      @db = open_cache_biblio(global_cache)
      @local_db = open_cache_biblio(local_cache, global: false)
      @db_name = global_cache
      @local_db_name = local_cache
    end

    def register_gems
      puts "[relaton] Info: detecting backends:"
      SUPPORTED_GEMS.each do |b|
        # puts b
        begin
          require b
        rescue LoadError
          puts "[relaton] Error: backend #{b} not present"
        end
      end
    end

    # The class of reference requested is determined by the prefix of the code:
    # GB Standard for gbbib, IETF for ietfbib, ISO for isobib, IEC or IEV for iecbib,
    # @param code [String] the ISO standard Code to look up (e.g. "ISO 9000")
    # @param year [String] the year the standard was published (optional)
    # @param opts [Hash] options; restricted to :all_parts if all-parts reference is required
    # @return [String] Relaton XML serialisation of reference
    def fetch(code, year = nil, opts = {})
      stdclass = standard_class(code) or return nil
      check_bibliocache(code, year, opts, stdclass)
    end

    def fetch_std(code, year = nil, stdclass = nil, opts = {})
      std = nil
      @registry.processors.each do |name, processor|
        std = name if processor.prefix == stdclass
      end
      unless std
        std = standard_class(code) or return nil
      end
      check_bibliocache(code, year, opts, std)
    end

    # def fetched(key)
    #   return @local_db.fetched key if @local_db
    #   return @db.fetched key if @db

    #   ""
    # end

    # The document identifier class corresponding to the given code
    def docid_type(code)
      stdclass = standard_class(code) or return [nil, code]
      _prefix, code = strip_id_wrapper(code, stdclass)
      [@registry.processors[stdclass].idtype, code]
    end

    # @param key [String]
    # @return [Hash]
    def load_entry(key)
      unless @local_db.nil?
        entry = @local_db[key]
        return entry if entry
      end
      @db[key]
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
        xml.documents do
          xml.parent.add_child db.all.join(" ")
        end
      end.to_xml
    end

    private

    # @param code [String] code of standard
    # @return [Symbol] standard class name
    def standard_class(code)
      @registry.processors.each do |name, processor|
        return name if /^#{processor.prefix}/.match(code) ||
          processor.defaultprefix.match(code)
      end
      allowed = @registry.processors.reduce([]) do |m, (_k, v)|
        m << v.prefix
      end
      warn "#{code} does not have a recognised prefix: #{allowed.join(', ')}"
      nil
    end

    # TODO: i18n
    # Fofmat ID
    # @param code [String]
    # @param year [String]
    # @param opts [Hash]
    # @param stdClass [Symbol]
    # @return [Array]
    def std_id(code, year, opts, stdclass)
      prefix, code = strip_id_wrapper(code, stdclass)
      ret = code
      ret += ":#{year}" if year
      ret += " (all parts)" if opts[:all_parts]
      ["#{prefix}(#{ret})", code]
    end

    # Find prefix and clean code
    # @param code [String]
    # @param stdClass [Symbol]
    # @return [Array]
    def strip_id_wrapper(code, stdclass)
      prefix = @registry.processors[stdclass].prefix
      code = code.sub(/^#{prefix}\((.+)\)$/, "\\1")
      [prefix, code]
    end

    def bib_retval(entry, stdclass)
      entry =~ /^not_found/ ? nil : @registry.processors[stdclass].from_xml(entry)
    end

    # @param code [String]
    # @param year [String]
    # @param opts [Hash]
    # @param stdclass [Symbol]
    def check_bibliocache(code, year, opts, stdclass)
      id, searchcode = std_id(code, year, opts, stdclass)
      db = @local_db || @db
      altdb = @local_db && @db ? @db : nil
      return bib_retval(new_bib_entry(searchcode, year, opts, stdclass), stdclass) if db.nil?

      db.delete(id) unless db.valid_entry?(id, year)
      if altdb
        db[id] ||= altdb[id]
        db[id] ||= new_bib_entry(searchcode, year, opts, stdclass)
        altdb[id] = db[id] if !altdb.valid_entry?(id, year)
      else
        db[id] ||= new_bib_entry(searchcode, year, opts, stdclass)
      end
      bib_retval(db[id], stdclass)
    end

    # hash uses => , because the hash is imported from JSON
    # @param code [String]
    # @param year [String]
    # @param opts [Hash]
    # @param stdclass [Symbol]
    # @return [Hash]
    def new_bib_entry(code, year, opts, stdclass)
      bib = @registry.processors[stdclass].get(code, year, opts)
      bib = bib.to_xml(bibdata: true) if bib.respond_to? :to_xml
      bib = "not_found #{Date.today}" if bib.nil? || bib.empty?
      bib
    end

    # if cached reference is undated, expire it after 60 days
    # @param bib [Hash]
    # @param year [String]
    # def valid_bib_entry?(bib, year)
    #   bib&.is_a?(Hash) && bib&.has_key?("bib") && bib&.has_key?("fetched") &&
    #     (year || Date.today - bib["fetched"] < 60)
    # end

    # @param dir [String] DB directory
    # @param global [TrueClass, FalseClass]
    # @return [PStore]
    def open_cache_biblio(dir, global: true)
      return nil if dir.nil?

      db = DbCache.new dir
      # if File.exist? dir
      if global
        unless db.check_version?
          FileUtils.rm_rf(Dir.glob(dir + "/*"), secure: true)
          warn "Global cache version is obsolete and cleared."
        end
        db.set_version
      elsif db.check_version? then db
      else
        warn "Local cache version is obsolete."
        nil
      end
      # else db.set_version
      # end
    end

    # Check if version of the DB match to the gem version.
    # @param cache_db [String] DB directory
    # @return [TrueClass, FalseClass]
    # def check_cache_version(cache_db)
    #   cache_db.transaction { cache_db[:version] == VERSION }
    # end

    # Set version of the DB to the gem version.
    # @param cache_db [String] DB directory
    # @return [Pstore]
    # def set_cache_version(cache_db)
    #   unless File.exist? cache_db.path
    #     cache_db.transaction { cache_db[:version] = VERSION }
    #   end
    #   cache_db
    # end

    # @param enstry [String] entry in XML format
    # @return [IsoBibItem::IsoBibliographicItem]
    # def from_xml(entry)
    #   IsoBibItem.from_xml entry # will be unmarshaller
    # end

    # @param [Hash{String=>Hash{String=>String}}] biblio
    # def save_cache_biblio(biblio, filename)
    #   return if biblio.nil? || filename.nil?
    #   File.open(filename, "w") do |b|
    #     b << biblio.reduce({}) do |s, (k, v)|
    #       bib = v["bib"].respond_to?(:to_xml) ? v["bib"].to_xml : v["bib"]
    #       s.merge(k => { "fetched" => v["fetched"], "bib" => bib })
    #     end.to_json
    #   end
    # end
  end
end
