require "yaml"
require_relative "registry"
require_relative "db_cache"

module Relaton
  class RelatonError < StandardError; end

  class Db
    # @param global_cache [String] directory of global DB
    # @param local_cache [String] directory of local DB
    def initialize(global_cache, local_cache)
      @registry = Relaton::Registry.instance
      @db = open_cache_biblio(global_cache, type: :global)
      @local_db = open_cache_biblio(local_cache, type: :local)
      @db_name = global_cache
      @local_db_name = local_cache
      static_db_name = File.expand_path "../relaton/static_cache", __dir__
      @static_db = open_cache_biblio static_db_name
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
      stdclass = standard_class(code) || return
      cd = combine_doc code, year, opts, stdclass
      return cd if cd

      check_bibliocache(code, year, opts, stdclass)
    end

    def combine_doc(code, year, opts, stdclass)
      if (refs = code.split " + ").size > 1
        reltype = "derivedFrom"
        reldesc = nil
      elsif (refs = code.split ", ").size > 1
        reltype = "complements"
        reldesc = RelatonBib::FormattedString.new content: "amendment"
      else return
      end

      doc = @registry.processors[stdclass].hash_to_bib docid: { id: code }
      ref = refs[0]
      updates = check_bibliocache(ref, year, opts, stdclass)
      doc.relation << RelatonBib::DocumentRelation.new(bibitem: updates, type: "updates") if updates
      refs[1..-1].each_with_object(doc) do |c, d|
        bib = check_bibliocache("#{ref}/#{c}", year, opts, stdclass)
        if bib
          d.relation << RelatonBib::DocumentRelation.new(type: reltype, description: reldesc, bibitem: bib)
        end
      end
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
      std = standard_class(code) or return nil unless std

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
      warn <<~WARN
        #{code} does not have a recognised prefix: #{allowed.join(', ')}.
        See https://github.com/relaton/relaton/ for instructions on prefixing and wrapping document identifiers to disambiguate them.
      WARN
    end

    # TODO: i18n
    # Fofmat ID
    # @param code [String]
    # @param year [String]
    # @param opts [Hash]
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
      prefix = @registry.processors[stdclass].prefix
      code = code.sub(/\u2013/, "-").sub(/^#{prefix}\((.+)\)$/, "\\1")
      [prefix, code]
    end

    # @param entry [String] XML string
    # @param stdclass [Symbol]
    # @param id [String] docid
    # @return [NilClass, RelatonIsoBib::IsoBibliographicItem,
    #   RelatonItu::ItuBibliographicItem, RelatonIetf::IetfBibliographicItem,
    #   RelatonNist::NistBibliongraphicItem, RelatonGb::GbbibliographicItem]
    def bib_retval(entry, stdclass, _id)
      entry.match?(/^not_found/) ? nil : @registry.processors[stdclass].from_xml(entry)
    end

    # @param code [String]
    # @param year [String]
    # @param opts [Hash]
    # @param stdclass [Symbol]
    # @return [NilClass, RelatonIsoBib::IsoBibliographicItem,
    #   RelatonItu::ItuBibliographicItem, RelatonIetf::IetfBibliographicItem,
    #   RelatonNist::NistBibliongraphicItem, RelatonGb::GbbibliographicItem,
    #   RelatonOgc::OgcBibliographicItem, RelatonCalconnect::CcBibliographicItem]
    def check_bibliocache(code, year, opts, stdclass) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
      id, searchcode = std_id(code, year, opts, stdclass)
      yaml = @static_db[id]
      return @registry.processors[stdclass].hash_to_bib YAML.safe_load(yaml) if yaml

      db = @local_db || @db
      altdb = @local_db && @db ? @db : nil
      if db.nil?
        bibentry = new_bib_entry(searchcode, year, opts, stdclass, db: db, id: id)
        return bib_retval(bibentry, stdclass, id)
      end

      db.delete(id) unless db.valid_entry?(id, year)
      if altdb
        # db[id] ||= altdb[id]
        db.clone_entry id, altdb
        db[id] ||= new_bib_entry(searchcode, year, opts, stdclass, db: db, id: id)
        altdb.clone_entry(id, db) if !altdb.valid_entry?(id, year)
      else
        db[id] ||= new_bib_entry(searchcode, year, opts, stdclass, db: db, id: id)
      end
      bib_retval(db[id], stdclass, id)
    end

    # @param code [String]
    # @param year [String]
    # @param opts [Hash]
    # @param stdclass [Symbol]
    # @param db [Relaton::DbCache,`NilClass]
    # @param id [String] docid
    # @return [String]
    def new_bib_entry(code, year, opts, stdclass, **args) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      bib = @registry.processors[stdclass].get(code, year, opts)
      bib_id = bib&.docidentifier&.first&.id

      # when docid doesn't match bib's id then return a reference to bib's id
      if args[:db] && args[:id] && bib_id && args[:id] !~ %r{#{Regexp.quote("(#{bib_id})")}}
        bid = std_id(bib.docidentifier.first.id, nil, {}, stdclass).first
        args[:db][bid] ||= bib_entry bib
        "redirection #{bid}"
      else
        bib_entry bib
      end
    end

    # @param bib [RelatonGb::GbBibliongraphicItem, RelatonIsoBib::IsoBibliographicItem,
    #   RelatonIetf::IetfBibliographicItem, RelatonItu::ItuBibliographicItem,
    #   RelatonNist::NistBibliongraphicItem, RelatonOgc::OgcBibliographicItem]
    # @return [String] XML or "not_found mm-dd-yyyy"
    def bib_entry(bib)
      if bib.respond_to? :to_xml
        bib.to_xml(bibdata: true)
      else
        "not_found #{Date.today}"
      end
    end

    # @param dir [String] DB directory
    # @param type [Symbol]
    # @return [Relaton::DbCache, NilClass]
    def open_cache_biblio(dir, type: :static)
      return nil if dir.nil?

      db = DbCache.new dir, type == :static ? "yml" : "xml"

      Dir["#{dir}/*/"].each do |fdir|
        next if type == :static || db.check_version?(fdir)

        FileUtils.rm_rf(Dir.glob(fdir + "/*"), secure: true)
        warn "[relaton] cache #{fdir}: version is obsolete and cache is cleared."
      end
      db
    end
  end
end
