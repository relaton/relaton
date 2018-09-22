require "pstore"
require_relative "registry"

module Relaton
  class RelatonError < StandardError; end

  class Db
    SUPPORTED_GEMS = %w[isobib ietfbib gbbib iecbib].freeze

    # @param global_cache [String] filename of global DB
    # @param local_cache [String] filename of local DB
    def initialize(global_cache, local_cache)
      register_gems
      @db = open_cache_biblio(global_cache)
      @local_db = open_cache_biblio(local_cache, global: false)
      @db_name = global_cache
      @local_db_name = local_cache
      @registry = Relaton::Registry.instance
    end

    def register_gems
      puts "[relaton] detecting backends:"
      SUPPORTED_GEMS.each do |b|
        puts b
        begin
          require b
        rescue LoadError
          puts "[relaton] backend #{b} not present"
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

    # The document identifier class corresponding to the given code
    def docid_type(code)
      stdclass = standard_class(code) or return [nil, code]
      prefix, code = strip_id_wrapper(code, stdclass)
      [@registry.processors[stdclass].idtype, code]
    end

    # @param key [String]
    # @return [Hash]
    def load_entry(key)
      unless @local_db.nil?
        entry = @local_db.transaction { @local_db[key] }
        return entry if entry
      end
      @db.transaction { @db[key] }
    end

    # @param key [String]
    # @param value [Hash]
    # @option value [Date] "fetched"
    # @option value [IsoBibItem::IsoBibliographicItem] "bib"
    def save_entry(key, value)
      @db.nil? or @db.transaction { @db[key] = value }
      @local_db.nil? or @local_db.transaction { @local_db[key] = value }
    end

    # list all entries as a serialization
    def to_xml
      db = @local_db || @db || return
      db.transaction do
        Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
          xml.documents do
            db.roots.reject { |key| key == :version }.
              each { |key| db[key]&.fetch("bib")&.to_xml(xml, {}) }
          end
        end.to_xml
      end
    end

    private

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
    def std_id(code, year, opts, stdclass)
      prefix, code = strip_id_wrapper(code, stdclass)
      ret = code
      ret += ":#{year}" if year
      ret += " (all parts)" if opts[:all_parts]
      ["#{prefix}(#{ret})", code]
    end

    def strip_id_wrapper(code, stdclass)
      prefix = @registry.processors[stdclass].prefix
      code = code.sub(/^#{prefix}\((.+)\)$/, "\\1")
      [prefix, code]
    end

    def bib_retval(entry)
      entry["bib"] == "not_found" ? nil : entry["bib"]
    end

    # @param code [String]
    # @param year [String]
    # @param opts [Hash]
    # @param stdclass [Symbol]
    def check_bibliocache(code, year, opts, stdclass)
      id, searchcode = std_id(code, year, opts, stdclass)
      db = @local_db || @db
      altdb = @local_db && @db ? @db : nil
      return bib_retval(new_bib_entry(searchcode, year, opts, stdclass)) if db.nil?
      db.transaction do
        db.delete(id) unless valid_bib_entry?(db[id], year)
        if altdb
          altdb.transaction do
            db[id] ||= altdb[id]
            db[id] ||= new_bib_entry(searchcode, year, opts, stdclass)
            altdb[id] = db[id] if !valid_bib_entry?(altdb[id], year)
            bib_retval(db[id])
          end
        else
          db[id] ||= new_bib_entry(searchcode, year, opts, stdclass)
          bib_retval(db[id])
        end
      end
    end

    # hash uses => , because the hash is imported from JSON
    # @param code [String]
    # @param year [String]
    # @param opts [Hash]
    # @param stdclass [Symbol]
    # @return [Hash]
    def new_bib_entry(code, year, opts, stdclass)
      bib = @registry.processors[stdclass].get(code, year, opts)
      bib = "not_found" if bib.nil?
      { "fetched" => Date.today, "bib" => bib }
    end

    # if cached reference is undated, expire it after 60 days
    # @param bib [Hash]
    # @param year [String]
    def valid_bib_entry?(bib, year)
      bib&.is_a?(Hash) && bib&.has_key?("bib") && bib&.has_key?("fetched") &&
        (year || Date.today - bib["fetched"] < 60)
    end

    # @param filename [String] DB filename
    # @param global [TrueClass, FalseClass]
    # @return [PStore]
    def open_cache_biblio(filename, global: true)
      return nil if filename.nil?
      db = PStore.new filename
      if File.exist? filename
        if global
          unless check_cache_version(db)
            File.delete filename
            warn "Global cache version is obsolete and cleared."
          end
          set_cache_version db
        elsif check_cache_version(db) then db
        else
          warn "Local cache version is obsolete."
          nil
        end
      else
        set_cache_version db
      end
    end

    def check_cache_version(cache_db)
      cache_db.transaction { cache_db[:version] == VERSION }
    end

    def set_cache_version(cache_db)
      unless File.exist? cache_db.path
        cache_db.transaction { cache_db[:version] = VERSION }
      end
      cache_db
    end

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
