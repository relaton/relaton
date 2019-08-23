# require "pstore"
require_relative "registry"
require_relative "db_cache"

module Relaton
  class RelatonError < StandardError; end

  class Db
    SUPPORTED_GEMS = %w[
      relaton_iso relaton_ietf relaton_gb relaton_iec relaton_nist relaton_itu
    ].freeze

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
    # @return [NilClass, RelatonIsoBib::IsoBibliographicItem,
    #   RelatonItu::ItuBibliographicItem, RelatonIetf::IetfBibliographicItem,
    #   RelatonNist::NistBibliongraphicItem, RelatonGb::GbbibliographicItem]
    def fetch(code, year = nil, opts = {})
      stdclass = standard_class(code) or return nil
      check_bibliocache(code, year, opts, stdclass)
    end

    # @param code [String]
    # @param year [String, NilClass]
    # @param stdclass [Symbol, NilClass]
    # @param opts [Hash]
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

    # The document identifier class corresponding to the given code
    # @param code [String]
    # @return [Array]
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
      ["#{prefix}(#{ret.strip})", code]
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

    # @param entry [String] XML string
    # @param stdclass [Symbol]
    # @return [NilClass, RelatonIsoBib::IsoBibliographicItem,
    #   RelatonItu::ItuBibliographicItem, RelatonIetf::IetfBibliographicItem,
    #   RelatonNist::NistBibliongraphicItem, RelatonGb::GbbibliographicItem]
    def bib_retval(entry, stdclass)
      entry =~ /^not_found/ ? nil : @registry.processors[stdclass].from_xml(entry)
    end

    # @param code [String]
    # @param year [String]
    # @param opts [Hash]
    # @param stdclass [Symbol]
    # @return [NilClass, RelatonIsoBib::IsoBibliographicItem,
    #   RelatonItu::ItuBibliographicItem, RelatonIetf::IetfBibliographicItem,
    #   RelatonNist::NistBibliongraphicItem, RelatonGb::GbbibliographicItem]
    def check_bibliocache(code, year, opts, stdclass)
      id, searchcode = std_id(code, year, opts, stdclass)
      db = @local_db || @db
      altdb = @local_db && @db ? @db : nil
      return bib_retval(new_bib_entry(searchcode, year, opts, stdclass), stdclass) if db.nil?

      db.delete(id) unless db.valid_entry?(id, year)
      if altdb
        # db[id] ||= altdb[id]
        db.clone_entry id, altdb
        db[id] ||= new_bib_entry(searchcode, year, opts, stdclass, db, id)
        altdb.clone_entry(id, db) if !altdb.valid_entry?(id, year)
      else
        db[id] ||= new_bib_entry(searchcode, year, opts, stdclass, db, id)
      end
      bib_retval(db[id], stdclass)
    end

    # @param code [String]
    # @param year [String]
    # @param opts [Hash]
    # @param stdclass [Symbol]
    # @return [String]
    def new_bib_entry(code, year, opts, stdclass, db = nil, id = nil)
      bib = @registry.processors[stdclass].get(code, year, opts)
      bib_id = bib&.docidentifier&.first&.id&.sub(%r{(?<=\d)-(?=\d{4})}, ":")
      if db && id && bib_id && id !~ %r{\(#{bib_id}\)}
        bid = std_id(bib.docidentifier.first.id, nil, {}, stdclass).first
        db[bid] ||= bib_entry bib
        "redirection #{bid}"
      else
        bib_entry bib
      end
    end

    def bib_entry(bib)
      if bib.respond_to? :to_xml
        bib.to_xml(bibdata: true)
      else
        "not_found #{Date.today}"
      end
    end

    # @param dir [String] DB directory
    # @param global [TrueClass, FalseClass]
    # @return [PStore]
    def open_cache_biblio(dir, global: true)
      return nil if dir.nil?

      db = DbCache.new dir
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
    end
  end
end
